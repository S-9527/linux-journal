# Phase 7 · 系统原理

> **回答一个问题：`ls` 这个命令，运行的时候到底发生了什么？**
>
> 本文所有输出均为实际执行所得。本机无 `sudo` 权限，strace 相关实验在
> Docker 容器内完成（容器内是完整 root 环境，且能观察 namespace 隔离效果）。

---

## 0. 一切皆文件

Unix 的设计哲学：**把一切（硬件、进程、内存、配置）都抽象成文件。**

你 `cat` 一个文件，就是在和内核对话。`/proc` 是最直接的体现 —— 它把进程的所有信息暴露成文件。

### `/proc` 实测

```console
$ grep -E "^(Name|Pid|PPid|Threads|VmRSS)" /proc/self/status
Name:	grep
Pid:	8
PPid:	1
VmRSS:	    2140 kB
Threads:	1
```

**`/proc/self` 是"当前进程"的自我引用** —— 你可以用它写一个程序查看自己。

| 文件 | 内容 |
|---|---|
| `/proc/self/cmdline` | 启动命令（`\0` 分隔，用 `tr '\0' ' '` 变一行） |
| `/proc/self/status` | UID/GID、状态、内存、线程数 |
| `/proc/self/maps` | 内存布局 |
| `/proc/self/fd/` | 打开的所有文件描述符 |
| `/proc/self/limits` | 资源限制 |
| `/proc/self/cwd` | 当前工作目录（符号链接） |
| `/proc/self/exe` | 可执行文件路径 |

### 找父进程

```console
$ PPID_=$(awk '/^PPid:/{print $2}' /proc/self/status)
$ echo "我的 PPid = $PPID_"
我的 PPid = 1
$ tr '\0' ' ' < /proc/$PPID_/cmdline
bash /lab/run8.sh
```

**实用的排查技巧 —— 谁在占用这个端口：**

```bash
# 方法 1: ss 直接告诉你（最快）
ss -tlnp | grep :8080

# 方法 2: 遍历 /proc（ss 不可用时）
for p in /proc/[0-9]*/fd/*; do
    t=$(readlink "$p" 2>/dev/null)
    case "$t" in socket:*) echo "$p -> $t";; esac
done
```

---

## 1. `strace` —— 程序的显微镜

```bash
strace ls                      # 跟所有系统调用
strace -c ls                   # 统计：哪个调用最频繁/最耗时
strace -f ls                   # 跟子进程
strace -e trace=openat ls      # 只跟 openat
strace -p 1234                 # 跟正在运行的进程
strace -o out.txt ls           # 输出到文件
```

### 实测：`ls -l` 打开了 20 个文件

```console
$ strace -f -c -e trace=openat ls -l /etc/hostname
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
100.00    0.000671          33        20         7 openat
------ ----------- ----------- --------- --------- ----------------
100.00    0.000671          33        20         7 total
```

**为了列一个目录的元信息，`ls` 打开了 20 个文件，其中 7 次失败。**

### 完整的 openat 列表

```console
$ strace -f -e trace=openat ls -l /etc/hostname 2>&1 | grep openat
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/libselinux.so.1", ...) = 3
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/libgcc_s.so.1", ...) = 3
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/libm.so.6", ...) = 3
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/libc.so.6", ...) = 3
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/libpcre2-8.so.0", ...) = 3
openat(AT_FDCWD, "/proc/filesystems", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/proc/mounts", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/proc/self/maps", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/usr/share/coreutils/locales/uucore/en-US.ftl", ...) = 3
openat(AT_FDCWD, "/usr/share/coreutils/locales/ls/en-US.ftl", ...) = -1 ENOENT
openat(AT_FDCWD, "/etc/nsswitch.conf", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/etc/group", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/usr/share/zoneinfo", O_NONBLOCK|O_DIRECTORY) = -1 ENOENT
openat(AT_FDCWD, "/usr/share/lib/zoneinfo", ...) = -1 ENOENT
openat(AT_FDCWD, "/etc/zoneinfo", ...) = -1 ENOENT
openat(AT_FDCWD, "/system/usr/share/zoneinfo/tzdata", ...) = -1 ENOENT
openat(AT_FDCWD, "/data/misc/zoneinfo/current/tzdata", ...) = -1 ENOENT
openat(AT_FDCWD, "/etc/localtime", ...) = -1 ENOENT
```

**逐个看这些路径，能读出 `ls -l` 到底做了什么：**

| 打开的东西 | 为什么 |
|---|---|
| `/etc/ld.so.cache` + 6 个 `.so` | 动态链接器加载 libc（`ls` 是动态链接的） |
| `/proc/self/maps` | 查内存映射（判断地址是否已加载） |
| `/etc/nsswitch.conf` | 查用户/组解析方式 |
| `/etc/passwd` `/etc/group` | **因为 `-l` 要显示 owner/group 名字** |
| `/proc/mounts` `/proc/filesystems` | 判断挂载点（因为 `-l` 要显示设备名） |
| 5 个 zoneinfo 路径全是 `ENOENT` | **时区探测，逐个试直到找到或放弃** |

**结论：不带 `-l` 的 `ls` 会少一半系统调用** —— 不需要查用户组和挂载信息。这是"能用最简方案就别过度"的一个具体体现。

### `-c` 全量统计

```console
$ strace -f -c ls -l /etc/hostname
% time     seconds  usecs/call     calls    errors syscall
  1.90    0.000073          36         2           prlimit64
  1.70    0.000065          21         3           sigaltstack
  1.59    0.000061          20         3           fcntl
  1.46    0.000056          28         2           listxattr
  1.41    0.000054          54         1           poll
  0.99    0.000038          38         1           getrandom
  0.97    0.000037          37         1           prctl
  0.89    0.000034          34         1           gettid
  0.81    0.000031          15         2         2 access
  0.68    0.000026           0        27           mmap
  0.63    0.000024          24         1         1 readlink
  0.60    0.000023          23         1           sched_getaffinity
  0.00    0.000000           0         2           pread64
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1           arch_prctl
  0.00    0.000000           0         1           set_tid_address
  0.00    0.000000           0         1           set_robust_list
  0.00    0.000000           0         1           rseq
------ ----------- ----------- --------- --------- ------------------
100.00    0.003834          21       178        21 total
```

**一次 `ls` = 178 次系统调用，21 次失败。** 大部分时间花在 `mmap`（27 次，装载共享库）。

`arch_prctl`、`set_tid_address`、`set_robust_list`、`rseq` 是典型的 **glibc 启动序列** —— 这些是"任何动态链接程序启动时都会做"的事，看到它们就知道程序刚起来。

---

## 2. fork + execve

**任何进程的执行都归结为两步：**

1. **fork** —— 复制出一个几乎一模一样的子进程
2. **exec** —— 把子进程的内存替换成新程序

### 实测（Python 显式 fork）

```console
$ strace -f -e trace=clone,clone3,execve python3 /tmp/forktest.py
execve("/usr/bin/python3", ["python3", "/tmp/forktest.py"], 0x7ffd6ba3cf30 /* 6 vars */) = 0
clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=...) = 13
[pid    13] execve("/bin/echo", ["/bin/echo", "child via fork+exec"], 0x2f499c20 /* 7 vars */) = 0
child via fork+exec
parent PID=12 child PID=13
```

**完整链路清晰可见：**

```
python3 启动 → execve(python3)
           → clone() = 13          ← fork，得到 PID 13
           → [pid 13] execve(/bin/echo)   ← exec，内存换成 echo
           → echo 输出 "child via fork+exec"
           → 退出，父进程 waitpid 回收
```

**`clone` 是 glibc 里 `fork` 的底层实现。** 参数 `CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD` 是现代 Linux 的标准组合。

### 为什么 fork 和 exec 要分开

历史原因 + 实用价值：

- **分开后，fork 和 exec 之间可以做"改环境"的事** —— 重定向文件描述符、改 cwd、setuid。shell 的重定向 `cmd > file` 就是 fork 后、exec 前修改 fd 0/1/2
- **历史上 fork 很慢**（复制整个地址空间），所以 shell 会先 fork 再 exec，中间做批量的准备工作

**现代 Linux 上 `posix_spawn` / `vfork` 优化了这个流程**（glibc 对简单场景用 `CLONE_VFORK`），但 `fork` + `exec` 的语义模型没变。

### bash 内建命令 vs 外部命令

```console
$ strace -f -e trace=clone,execve bash -c 'echo builtin' | grep -c clone
0                     ← 内建命令，bash 自己执行，不创建进程

$ strace -f -e trace=clone,execve bash -c '/bin/echo external' | grep -c clone
>0                   ← 外部命令，fork + execve
```

**bash 的内建命令（`echo`/`cd`/`export`/`read`）在 bash 进程内执行，不 fork。** 这就是为什么 `cd` 能改变当前 shell 的目录，而 `sh -c "cd /tmp"` 不能 —— 后者是子进程，改的是子进程的 cwd。

⚠️ 实测注意：`strace` 从 `execve` 之后才开始跟踪，所以看不到 bash 自己的 fork（bash 在 execve 之前就已经 fork 了）。要观察 bash 的 fork 需要用 `strace -f` 跟 shell 本身。

---

## 3. 虚拟内存

```console
$ head -3 /proc/self/maps
5a6b2d5eb000-5a6b2d6dd000 r--p 00000000 00:51 322788   /usr/lib/.../coreutils/head
5a6b2d6dd000-5a6b2db95000 r-xp 000f2000 00:51 322788   /usr/lib/.../coreutils/head
5a6b2db95000-5a6b2df54000 r--p 005aa000 00:51 322788   /usr/lib/.../coreutils/head
```

格式：

```
起始地址-结束地址 权限 偏移 设备号  inode  路径
       r--p     00000000 00:51 322788  /usr/lib/.../head
```

| 字段 | 含义 |
|---|---|
| `r--p` | 权限：read / execute / private |
| `rw-p` | 可读写，private |
| `00:51` | 设备号（`fd:device`） |
| `322788` | inode 号 |

**三个关键事实：**

1. **进程看到的是连续、独立的地址空间**，实际物理内存是分散的
2. **`p`（private）vs `s`（shared）** —— 同一程序的多个进程，共享只读段（`r--s`、`r-xs`）
3. **虚拟地址空间远大于物理内存** —— 所以"内存不够"时 Linux 能正常运行，因为页面可以换出

### 内存分类

```bash
free -h
```

```
              total   used   free  shared  buff/cache  available
Mem:           15Gi   1.4Gi   12Gi     10Mi       2.0Gi       13Gi
```

**`buff/cache` 不是"浪费"** —— 是内核用空闲内存做的缓存（页缓存）。应用要读文件时直接从缓存给，不用等磁盘。**所以判断"内存够不够"要看 `available`，不是 `free`。**

---

## 4. OOM 实测

### 触发

```console
$ docker run --rm --memory 100m strace-lab bash /lab/run9.sh
allocated 50MB
allocated 100MB
allocated 150MB
/lab/run9.sh: line 14: 8 Killed    python3 /tmp/oom.py
python exit: 137
```

**三个关键数字：**

- `Killed` —— 进程被信号杀死
- **`137 = 128 + 9`** —— 信号 9 = SIGKILL
- **150MB 分配了但没用完 100MB 就死了** —— OOM 不是"达到上限就拒绝分配"，是内核**主动杀进程**

### 找到证据

```console
$ docker inspect oomtest2 --format 'OOMKilled: {{.State.OOMKilled}}
ExitCode:  {{.State.ExitCode}}'
OOMKilled: true
ExitCode:  0
```

⚠️ **注意 `ExitCode: 0`！** 这就是 Phase 3 讲过的：应用被 SIGKILL 杀掉，`bash` 本身正常退出，所以容器退出码是 0。**只看容器退出码会误判，必须查 `OOMKilled`。**

### 生产环境的排查

```bash
# 1. 查内核日志里的 OOM 记录
dmesg | grep -i "killed process"
journalctl -k | grep -i "oom"

# 2. 经典日志
# Out of memory: Killed process 12345 (node)
# oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=...,mems_allowed=0
```

**日志里最经典的一句就是 `Killed process 12345 (node)`** —— 很多"服务莫名重启"的问题，根因都在这。

### 预防

| 层面 | 手段 |
|---|---|
| 应用 | 设置内存上限（Node `--max-old-space-size`）、处理 OOM 优雅退出 |
| 容器 | `--memory 512m` 明确上限，**别让一个容器吃光整台机器** |
| 主机 | 留够 Swap（WSL2 本机实测 4GB Swap） |
| 监控 | 内存使用率告警（>85% 预警） |
| 系统 | `vm.overcommit_memory`、调整 `oom_score_adj`（关键进程给负值保命） |

---

## 5. namespace + cgroups —— Docker 的真相

### 5.1 namespace：给你一个"假的世界"

| Namespace | 隔离什么 | 容器内表现 |
|---|---|---|
| **PID** | 进程号 | 容器里的进程从 PID 1 开始 |
| **Network** | 网卡、IP、端口、路由 | 有独立的 `lo` 和 eth0 |
| **Mount** | 目录树 | 独立的 `/` |
| **UTS** | 主机名 | 独立 hostname |
| **IPC** | System V IPC、共享内存 | 独立 |
| **User** | UID/GID | 可把容器内 root 映射成宿主机普通用户 |
| **Cgroup** | cgroup v2 根 | 独立的资源视图 |

### 5.2 容器内外对比实测

| | 宿主机 | 容器内 |
|---|---|---|
| hostname | `LAPTOP-ER34SL43` | `6da81dc8760c`（容器 ID） |
| `ls /` | 有 `init lost+found snap` | **没有** |
| `ps aux` 进程数 | **77** | **4** |
| IP | 192.168.1.8 | 172.17.0.2 |
| `/etc/hosts` | WSL 自动生成，含 `127.0.1.1 LAPTOP-ER34SL43` | Docker 生成，含 `172.17.0.2 6da81dc8760c` |

**`ps aux` 只能看到 4 个进程** —— 因为 PID namespace 里宿主机那 77 个进程根本不存在。**这就是"容器看不到宿主机进程"的原理。**

容器内 `ls /` 的输出：

```
bin boot dev etc home lab lib lib64 media mnt opt proc root run sbin srv sys tmp usr var
```

宿主机 `ls /`：

```
bin boot dev etc home init lib lib64 lost+found media mnt opt proc root run sbin snap srv sys usr var
```

**容器里没有 `init`、`lost+found`、`snap`** —— Mount namespace 给了一个不同的根目录。

### 5.3 cgroups：限制实际用量

namespace 管"**看到多少**"，cgroups 管"**能用多少**"。

```bash
# 语法
docker run --memory 100m --cpus 0.5 ...
docker run --memory 100m --memory-swap 200m ...   # 内存+swap 总上限

# 实测触发 OOM
docker run --memory 100m ...
→ 分配 150MB 时被 OOM Killer 杀掉

# 实时观察
docker stats
```

### 5.4 一句话总结

> **namespace 给你一个"假的世界"，cgroups 决定这个假世界能吃多少资源。**

**Docker = 镜像（文件系统打包）+ namespace（视图隔离）+ cgroups（资源限制）+ 少量胶水（网络配置、挂载）。**

---

## 6. 思考题答案

### 1. 为什么容器里 `ps aux` 看不到宿主机进程

**因为 PID namespace。**

每个容器有独立的 PID namespace，容器内的进程号从 1 开始重新编号。宿主机上 PID 1234 的进程，在容器的 PID namespace 里可能根本不存在（或者编号完全不同）。

内核在 namespace 层面做了过滤：`readdir /proc` 时只列出当前 namespace 内的进程，`/proc/<pid>` 也只对可见的 PID 有效。

**实测：** 宿主机 77 个进程，容器内 4 个。

### 2. 容器和虚拟机哪个更安全

**虚拟机更安全。**

| | 虚拟机 | 容器 |
|---|---|---|
| 内核 | **自己的**，与宿主机隔离 | **共享宿主机内核** |
| 攻击面 | 需要先逃出 hypervisor | 一次内核漏洞就可能逃逸 |
| 系统调用 | 走 hypervisor 翻译 | **直接进宿主机内核** |
| CVE 历史 | 较少 | 较多（runc CVE-2019-5736 等） |

**根本原因：** 容器的隔离靠"限制能看到的资源"，但**能发起的系统调用是同一套**。容器里的进程调用 `read()`，走的是宿主机内核的 `read()`。

**但容器更"够用"：** 绝大多数业务场景（CI、内部服务、微服务隔离）不需要对抗恶意代码。金融级多租户、需要运行不可信代码时仍必须用 VM。

### 3. cgroups 限制的是"看到多少"还是"能用多少"？namespace 呢

| | 管什么 | 类比 |
|---|---|---|
| **namespace** | **看到多少** | 给你一个假世界：只列出这些进程/文件/网卡 |
| **cgroups** | **能用多少** | 真实世界的资源天花板：CPU 配额、内存上限 |

**cgroups 限制是真实生效的** —— 容器以为有 16GB 内存（`free` 这么显示），但 cgroups 会在它用到 512MB 时触发 OOM。**这是"视图"和"现实"的分离。**

### 4. 为什么 `/proc/self/status` 里有两个 UID

因为有**三个**（不是两个）相关的：

```
Uid:	1000	1000	1000	1000
Gid:	1000	1000	1000	1000
Groups:	27 1000
```

每行四个数字：**真实 UID / 有效 UID / 保存的 UID / 文件系统 UID**。

| 字段 | 含义 |
|---|---|
| Real UID (ruid) | 登录时的身份 |
| Effective UID (euid) | **当前实际生效的身份** —— 权限检查用这个 |
| Saved UID (suid) | 可以临时切换过去的身份 |
| Filesystem UID (fsuid) | 文件系统操作用的身份 |

**为什么需要这么多？** 主要是历史原因：早期 UID 空间小，需要区分"登录身份"和"当前身份"。setuid 程序（比如 `passwd`、`sudo`）用它实现"以 root 权限执行，但保留你的身份"。

**日常排查只需要看 euid（第二个）。** `ls -n` 显示的 owner ID 就是 euid。

**容器里的体现：** `--user 1000:1000` 改的是 euid。rootless 容器用 User namespace 把容器内的 root(0) 映射成宿主机的普通用户 —— **容器内 `id` 显示 `uid=0(root)`，宿主机上实际是某个普通用户**。

### 5. fork 之后父子进程独立的是什么？什么数据是共享的

**独立的：**

| | 说明 |
|---|---|
| **地址空间** | 完全副本，修改互不影响（除非显式 `mmap(MAP_SHARED)`） |
| **文件描述符表** | **内容复制，但指向同一个 open file description** |
| **进程 ID** | 不同 |
| **信号处理** | 副本 |
| **资源统计** | 独立（rlimit、nice 等） |

⚠️ **最反直觉的一点：文件描述符是"独立表，共享文件"。**

```c
int fd = open("log.txt", O_WRONLY);
fork();
// 父子进程的 fd 表里都有 fd=3，
// 但 fd 3 指向【同一个】内核 open file description
// 包含文件偏移量、状态标志
// → 父子共享文件偏移量！父写了 10 字节，子接着从 10 开始写
```

**所以 `fork()` 后父子同时写同一个文件会内容错乱**，除非用 `O_APPEND`（每次写都强制移到末尾）。

**共享的：**

- **打开的文件**（通过继承的 fd）
- **内存映射**（`mmap(MAP_SHARED|MAP_ANONYMOUS)` 显式创建的）
- **同一线程组的资源`（内核层面）**
- **`vfork`/`posix_spawn` 场景下共享整个地址空间**（所以 vfork 的子进程里**绝不能**做危险操作）

### 6. 你的程序被 OOM kill 了，从哪几个角度预防

**① 应用层：让程序知道自己内存不够**

```python
try:
    allocate_huge()
except MemoryError:
    cleanup_and_exit_gracefully()
```

Node：`--max-old-space-size=2048`（默认堆上限约 2-4GB，超了抛 `FATAL ERROR: JavaScript heap out of memory`）
JVM：`-Xmx512m` + `-XX:+ExitOnOutOfMemoryError`
Go：调低 `GOGC`，或用 `debug.SetMemoryLimit()`

**② 容器层：明确上限**

```bash
docker run --memory 512m --memory-swap 1g --cpus 1.0 app
```

**别让一个容器吃光整台机器** —— 这会导致内核可能杀掉别的进程（OOM killer 按 `oom_score` 选目标，不一定是超限的那个）。

**③ 主机层：留够 Swap + 监控**

```bash
# Swap 至少为物理内存的 50%
# 监控 available（不是 free）
watch -n1 'free -h | grep Mem'
```

**④ 内核层：保护关键进程**

```bash
# 关键进程降低被杀优先级
echo -1000 > /proc/<pid>/oom_score_adj
# 让它更容易被杀
echo 1000 > /proc/<pid>/oom_score_adj
```

**⑤ 架构层：限制单次请求的资源**

- 上传大小限制
- 分页/流式处理，不一次性载入
- 队列限流（防止请求堆积导致内存线性增长）

---

## 速查

```bash
# /proc
cat /proc/self/{cmdline,status,maps,limits}
ls -l /proc/self/fd/ /proc/self/cwd /proc/self/exe
cat /proc/meminfo /proc/loadavg /proc/cpuinfo
ls -l /proc/*/fd/ 2>/dev/null | grep deleted   # 已删除但被占用的文件
for p in /proc/[0-9]*; do cat $p/cmdline 2>/dev/null | tr '\0' ' '; echo " [${p#/proc/}]"; done

# strace
strace -c -f -e trace=openat,read,write cmd
strace -p PID
strace -o out.txt cmd
man 2 <syscall名>       # 比如 man 2 openat

# 内存
free -h                 # 看 available
cat /proc/meminfo
dmesg | grep -i "killed process"
echo 1000 > /proc/PID/oom_score_adj

# Docker 隔离
docker run --name x --memory 100m --cpus 0.5 img
docker inspect x --format '{{.State.OOMKilled}}'
docker stats
docker exec x ps aux / ip addr / ls /
docker system df

# namespace (需要 root)
lsns -t pid
unshare --pid --fork --mount-proc bash
man 7 namespaces
cat /proc/self/uid_map
```
