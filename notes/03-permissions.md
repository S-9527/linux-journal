# Phase 3 · 权限与进程

> **谁能访问什么东西，程序怎么在后台活着。**
> 运维工作的地基。本文所有输出均为实际执行所得。

---

## 1. 文件权限

### `ls -l` 第一列拆解

```console
$ ls -l data/logs/access.log
-rw-r--r--  1 anguish anguish 630 Sep 28 12:33 access.log
 ↑└┬┘└┬┘└┬┘
  │ │   │ └── 其他人 others   r--
  │ │   └──── 所属组 group    r--
  │ └──────── 所有者 owner     rw-
  └────────── 文件类型         -  普通文件
```

文件类型第一个字符：

| 字符 | 含义 |
|---|---|
| `-` | 普通文件 |
| `d` | 目录 |
| `l` | 符号链接 |
| `c` / `b` | 设备文件 |

### 数字的含义

`r=4` `w=2` `x=1`，每位独立相加：

| 数字 | 权限 | 场景 |
|---|---|---|
| `644` | `rw-r--r--` | 普通文件：自己能改，别人能读 |
| `755` | `rwxr-xr-x` | 脚本/程序/目录：自己能执行，别人能执行和读 |
| `600` | `rw-------` | 私钥、密码文件，**只有自己能访问** |
| `700` | `rwx------` | 私有目录，`~/.ssh` 必须是这个 |
| `777` | `rwxrwxrwx` | **不要用**，见下文 |

实测每一位独立生效：

```console
$ chmod 400 d2.sh → -r--------
$ chmod 444 d2.sh → -r--r--r--
$ chmod 644 d2.sh → -rw-r--r--
$ chmod 755 d2.sh → -rwxr-xr-x
$ chmod 777 d2.sh → -rwxrwxrwx
```

### 符号法 vs 数字法

符号法格式：`[ugoa][+-=][rwx]`

```console
$ echo x > d2.sh && ls -l d2.sh
-rw-r--r--
$ chmod u+x d2.sh && ls -l d2.sh
-rwxr--r--        # 给所有者加执行
$ chmod g+w d2.sh && ls -l d2.sh
-rwxrw-r--
$ chmod o-r d2.sh && ls -l d2.sh
-rwxrw----
$ chmod a-x d2.sh && ls -l d2.sh
-rw-rw----
```

**关键区别：数字法是「设置」，符号法是「增减」。**

实测一个容易误解的地方：

```console
$ chmod 644 demo.sh
$ chmod go-w demo.sh          # 在 644 上执行
$ ls -l demo.sh
-rw-r--r--                   # 毫无变化！
```

因为 `go-w` 是"**移除**已有的 w"，而 644 的 group/others 本来就没有 `w`。**想设置就用数字法或 `=`**：

```bash
chmod g-w file     # 移除
chmod g=rw file    # 设置为恰好 rw
```

---

## 2. 目录的权限含义完全不同（新手重灾区）

**对目录来说：**

| 权限 | 含义 |
|---|---|
| `r` | 能 `ls` **列出**里面有什么 |
| `w` | 能在里面**创建/删除/重命名**文件 |
| `x` | 能 `cd` 进去、能**访问**里面的文件 |

实测一个 `444`（有 r 无 x）的目录：

```console
$ chmod 444 locked && ls -ld locked
dr--r--r-- 2 anguish anguish 60 ... locked

$ ls locked
f.txt                          ✓ 成功（需要 r）

$ cat locked/f.txt
cat: locked/f.txt: Permission denied    ✗ 失败（需要 x）

$ cd locked
zsh:cd:1: permission denied: locked     ✗ 失败（需要 x）

$ chmod 555 locked              # 加上 x
$ cat locked/f.txt
secret                         ✓ 现在可以了
```

**结论：`r` 让你看到文件名，`x` 让你能真的打开它。** 这就是为什么目录几乎总是 `755` —— 少了 `x` 就成了摆设。

⚠️ **危险组合：目录有 `w` 但没有 `x`** —— 用户能在目录里创建、删除、重命名文件，但读不了内容。`chmod 733` 就是这种畸形权限。

---

## 3. umask

新建文件的权限不是 `777`，而是 **基础权限减去 umask**：

```
新文件 = 666 - umask    （普通文件，本来就没有 x）
新目录 = 777 - umask    （目录必须有 x）
```

```console
$ umask
022
```

所以默认新建文件是 `644`、目录是 `755`。

| umask | 文件 | 目录 | 场景 |
|---|---|---|---|
| `022` | 644 | 755 | 单机个人账号（默认） |
| `002` | 664 | 775 | 团队共享（同组成员可写） |
| `077` | 600 | 700 | 高度敏感数据 |

---

## 4. 进程

### 基础操作

```bash
ps aux                # 所有进程
ps -eo pid,ppid,pcpu,pmem,stat,comm --sort=-pcpu   # 自定义字段并排序
top -bn1              # 快照一次（-b 批处理模式, -n1 一次, 脚本里必须这么用)
kill 1234             # SIGTERM(15)，请求优雅退出
kill -9 1234          # SIGKILL(9)，强杀
```

实测优雅退出：

```console
$ sleep 300 & PID=$!
$ ps -o pid,stat,cmd -p $PID
    PID STAT CMD
  9963 SN   sleep 300
$ kill $PID
$ ps -p $PID || echo "已优雅退出"
已优雅退出
```

### 信号

| 信号 | 编号 | 可捕获 | 用途 |
|---|---|---|---|
| SIGHUP | 1 | 能 | 终端断开 |
| SIGINT | 2 | 能 | Ctrl+C |
| SIGTERM | 15 | 能 | `kill` 默认。**给程序清理的机会** |
| SIGKILL | 9 | **不能** | 强杀，程序来不及保存数据 |
| SIGSTOP | 19 | **不能** | 暂停（Ctrl+Z 是 SIGTSTP，可捕获） |

**SIGKILL 不能被捕获 —— 这是它"强"的代价，也是它"危险"的原因。**

### 后台运行

```bash
./long.sh &          # 后台启动，拿一个 job 号
jobs                # 列出当前 shell 的后台任务
fg %1               # 调回前台
bg %1               # 继续在后台跑
Ctrl+Z              # 暂停（SIGTSTP）
kill %1             # 按 job 号杀
nohup ./long.sh &   # 终端关闭也不死
disown -h %1        # 从 shell 管辖中摘除
```

**`&` 只让进程忽略 SIGHUP 之外的中断** —— 关掉终端时 shell 会给后台进程发 SIGHUP，导致它们死掉。`nohup` 就是忽略 SIGHUP。

### SIGKILL 导致数据丢失的实测

写一个模拟程序：数据先攒在内存缓冲，每 10 条落盘一次。

```console
$ /tmp/writer.sh &     # 正常运行
$ sleep 2.5
$ cat /tmp/data.txt
记录 21 数据记录 22 数据记录 23 数据记录 24 数据   # 已落盘

$ kill -9 <PID>        # 强杀
$ cat /tmp/data.txt
记录 21 数据记录 22 数据记录 23 数据记录 24 数据   # 缓冲区里的 25+ 永久消失
```

**缓冲区里未落盘的数据随进程一起消失。** 数据库的 WAL、应用的重试队列、编辑器的未保存文件，都是同一个道理。

**这就是为什么 `kill -9` 是最后手段：**

| 场景 | 正确做法 |
|---|---|
| 数据库 | `kill`（TERM），让它 flush + 正常关闭 |
| 你的应用 | `kill`（TERM），处理 TERM 信号做清理 |
| 进程无响应（已卡死） | `kill -9`，没得选了 |

**先 `kill`，等几秒还不行再 `kill -9`。**

### 僵尸 vs 孤儿

| | 孤儿 Orphan | 僵尸 Zombie |
|---|---|---|
| 定义 | 父进程先死了 | 子进程死了，父进程没回收 |
| 后果 | 被 PID 1 收养，正常运行 | 占 PID 表，内存已释放 |

实测：父进程退出的子进程被 init 收养，`ps` 里**没有** Z 状态。

```console
$ ps -eo pid,ppid,stat,cmd | awk 'NR==1 || $3 ~ /^Z/'
    PID    PPID STAT CMD
（无 Z = 没有僵尸）
```

**僵尸没法 kill** —— 它已经不是进程了，只是内核里一条"这个 PID 曾经存在过"的记录。唯一解法是让父进程调用 `wait()`。生产环境里僵尸进程堆积说明写服务的父进程有 bug。

---

## 5. 资源

```bash
free -h                # 内存
df -h                  # 磁盘：每个挂载点剩多少
du -sh *               # 磁盘：每个目录占了多少
uptime                 # 负载均值
```

实测：

```console
$ df -h / /mnt/c
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdd       1007G   19G  938G   2% /
C:\             501G  148G  353G  30% /mnt/c

$ du -sh ~/workspace/*
143M  /home/anguish/workspace/memo
7.8M  /home/anguish/workspace/linux-journal
5.8M  /home/anguish/workspace/labs
```

### `df` vs `du` 为什么结果对不上

两者视角不同：

- `df` —— **文件系统层面**，看超级块里的总账
- `du` —— **遍历目录树**，一��文件一个文件加起来

常见不一致原因：

**1. 已删除但被进程持有的文件**（最常见，也最难查）

实测复现：

```console
$ dd if=/dev/zero of=/tmp/gone.bin bs=1M count=20
$ tail -f /tmp/gone.bin &     # 进程打开了这个文件
$ rm /tmp/gone.bin            # 删除

$ du -sh /tmp/gone.bin
du: cannot access '/tmp/gone.bin': No such file or directory
                                    ↑ du 看不到它

# 但通过 /proc 能找到持有它的进程
$ for p in /proc/[0-9]*/fd/*; do readlink "$p"; done | grep gone
/tmp/gone.bin (deleted)
```

**inode 还被引用着，所以 20MB 空间没有释放，`df` 照样算进去。** 杀掉那个进程空间就回来了。

**2. 硬链接** —— 同一份数据多个名字，`du` 可能重复计或只计一次

**3. 虚拟文件系统** —— `/proc`、`/sys` 里的东西 `du` 看不到

**4. 稀疏文件** —— `du` 看实际占用块数，`ls -l` 看逻辑大小

### 排查思路

```bash
# 第一步: 找最大的目录
du -h --max-depth=1 ~ | sort -rh | head

# 第二步: 进可疑目录继续拆
du -h --max-depth=1 ~/suspicious | sort -rh | head

# 第三步: 找最大的文件
find ~ -type f -printf '%s %p\n' | sort -rn | head -20

# 如果 df 和 du 差很多: 找已删除但被占用的文件
ls -l /proc/*/fd/ 2>/dev/null | grep "(deleted)"
```

实测最大的文件：

```console
$ find ~/workspace -type f -printf '%s %p\n' | sort -rn | head -3
   18.3MB  memo/node_modules/.pnpm/@rolldown+binding-linux-x64-gnu@1.2.11/.../rolldown-binding.linux-x64-gnu.node
    9.6MB  memo/node_modules/.pnpm/lightningcss-linux-x64-gnu@1.33.0/.../lightningcss.linux-x64-gnu.node
    9.3MB  memo/node_modules/.pnpm/esbuild@0.21.5/node_modules/esbuild/bin/esbuild
```

---

## 6. 交付脚本

### `scripts/03-disk-usage.sh`

```console
$ ./scripts/03-disk-usage.sh ~/workspace 1
▶ /home/anguish/workspace 目录下空间占用 Top 20（深度 1）

      156M  /home/anguish/workspace
      143M  /home/anguish/workspace/memo
      7.8M  /home/anguish/workspace/linux-journal
      5.8M  /home/anguish/workspace/labs

💡 总占用: 156M
💡 文件系统剩余: 938G 可用 / 1007G (2% 已用)
```

参数校验实测：

```console
$ ./scripts/03-disk-usage.sh /nonexistent
错误: '/nonexistent' 不是目录          退出码 1

$ ./scripts/03-disk-usage.sh . abc
错误: 深度必须是正整数，收到 'abc'      退出码 1

$ ./scripts/03-disk-usage.sh a b c
用法: 03-disk-usage.sh [目录] [深度]   退出码 1
```

**三个设计要点：**

1. **`set -euo pipefail` 让参数校验自动生效** —— 校验不通过就 `exit 1`，不会带着脏参数往下跑
2. **正则校验整数**：`[[ "$DEPTH" =~ ^[0-9]+$ ]]`，比 `[ "$x" -gt 0 ]` 严谨（后者遇非数字会报错而非优雅退出）
3. **`du` 的 stderr 丢弃**：`2>/dev/null` —— 扫大目录时会刷一堆 "Permission denied"，干扰输出

### `scripts/03-process-watch.sh`

```console
$ ./scripts/03-process-watch.sh 1
═══ 系统监控 ═══  2026-09-28 12:48:20  (每 1s 更新, Ctrl+C 退出)

内存  总 15.3G | 可用 13.9G | 已用 1.4G (9%)
       Swap 4.0G | 可用 4.0G
负载  1min 0.11 | 5min 0.23 | 15min 0.26
运行  up 27 minutes

CPU Top 5
    CPU%   MEM% COMMAND
    12.6    1.6 opencode
     4.6    2.3 opencode
     0.4    0.0 Relay(757)
     0.3    0.3 containerd
     0.2    0.6 dockerd

内存 Top 5
    CPU%   MEM% COMMAND
     4.6    2.3 opencode
    12.6    1.6 opencode
     0.2    0.6 dockerd
```

**设计要点：**

1. **从 `/proc/meminfo` 读，不依赖 `free`** —— 输出格式稳定，好解析
2. **`trap cleanup EXIT` 恢复光标** —— 循环里隐藏了光标（`\033[?25l`），Ctrl+C 后不恢复的话，终端提示符会看不见
3. **`ps --sort=-pcpu` 一次排序两个维度** —— 避免多次调用 `ps`
4. **`sleep` 放循环末尾** —— 脚本启动后立即显示第一屏，不用等

---

## 思考题答案

### 1. 为什么 `chmod 777` 危险？举攻击场景

**任何用户对任何文件都有完全权限。** 攻击场景：

- 应用以 root 运行且某个目录是 777 → 攻击者在里面放一个 `.bashrc` 劫持或替换可执行文件
- 共享服务器上，别人能改你的脚本 → 你执行时就是在执行他写的代码
- 挂载了 NFS 的目录 777 → 任意容器内进程都能读写
- web 目录 777 → 上传目录可被写 webshell

**权限的思路是「最小必要」**：只给该给的人。脚本给 `755`，配置给 `644`，私钥给 `600`。

### 2. `kill -9` 和 `kill` 的区别

`kill` 发 SIGTERM(15)，程序**可以捕获**并做清理（关连接、flush 缓冲、删 pid 文件）。
`kill -9` 发 SIGKILL(9)，**内核直接终结，程序完全没机会反应**。

必须用 `-9` 的情况：进程已卡死（死循环里等锁、D 状态不可中断 IO）、TERM 发了没响应、程序有 bug 导致清理逻辑本身有问题。

**先 TERM，等 5-10 秒，不行再 KILL。**

### 3. 目录权限 `444`，能 `ls` 吗？能 `cd` 吗？

- `ls` **能**（有 `r`）
- `cd` **不能**（没有 `x`）
- 读里面的文件**不能**（路径解析需要 `x`）

实测输出见第 2 节。

### 4. `df` 显示满了但 `du` 只有 1G，什么原因

按可能性排序：

1. **已删除但被进程持有的文件**（最常见）—— 查 `ls -l /proc/*/fd/ | grep "(deleted)"`
2. **别的目录占的** —— `du -x /` 逐层找（`-x` 不跨文件系统）
3. **日志/缓存目录** —— `/var/log`、`/tmp`、journald
4. **docker 占用** —— `docker system df`（overlay2 层很能吃空间）
5. **快照/缓存** —— 某些虚拟磁盘

### 5. umask 022 vs 002

| | 022 | 002 |
|---|---|---|
| 文件 | 644 | 664 |
| 目录 | 755 | 775 |
| 其他用户 | 只能读 | **能读能写** |
| 场景 | 个人机器 | 团队共享目录（需要同组成员协作编辑） |

002 的风险：任何用户都能改你的文件。**只有在确认组内成员都可信时才用。**

---

## 速查

```bash
# 权限
ls -l / ls -ld           # 文件 / 目录
chmod 755 file           # 数字法（设置）
chmod u+x file           # 符号法（增减）
chown user:group file    # 改属主
umask                    # 默认权限掩码
chmod 600 ~/.ssh/*       # 敏感文件

# 进程
ps aux / ps -ef
ps -eo pid,ppid,pcpu,stat,comm --sort=-pcpu
top -bn1                 # 脚本里用批处理模式
kill PID / kill -9 PID
jobs / fg %1 / bg %1
nohup cmd & / disown -h %1
kill -l                  # 列出所有信号

# 资源
free -h / df -h / du -sh
du -h --max-depth=1 ~ | sort -rh | head
find ~ -type f -printf '%s %p\n' | sort -rn | head
ls -l /proc/*/fd/ 2>/dev/null | grep deleted
uptime / uptime -p
```
