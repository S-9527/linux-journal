# 笔记索引

> Linux 学习笔记，全部命令输出均为实际执行验证。
> 环境：Ubuntu 26.04 LTS (WSL2) / bash / gh 2.46.0 / Docker 29.6.2

---

## 阅读顺序

| # | 笔记 | 核心问题 | 配套脚本 |
|---|---|---|---|
| 1 | [文件系统与管道](01-filesystem.md) | `\|` 和 `>` 到底怎么工作 | [`01-stats.sh`](../scripts/01-stats.sh) |
| 2 | [文本三剑客](02-text.md) | grep 找、sed 改、awk 取列的分界 | — |
| 3 | [权限与进程](03-permissions.md) | 谁能访问什么，程序怎么活着 | [`03-disk-usage.sh`](../scripts/03-disk-usage.sh) [`03-process-watch.sh`](../scripts/03-process-watch.sh) |
| 4 | [Shell 与 CI](04-shell.md) | `set -euo pipefail` 和 Actions 到底是什么 | [`04-backup.sh`](../scripts/04-backup.sh) |
| 5 | [网络与运维](05-network.md) | 怎么和外界说话，怎么远程管服务器 | [`05-port-check.sh`](../scripts/05-port-check.sh) |
| 6 | [Docker](06-docker.md) | 把环境打包带走 | [Dockerfile](../labs/06-docker/stats/Dockerfile) [compose](../labs/06-docker/docker-compose.yml) |
| 7 | [系统原理](07-internals.md) | `ls` 运行的时候发生了什么 | — |

---

## 如果只读三篇

**1. [Phase 2 · awk 的字符串陷阱](02-text.md#4-awk-的字符串陷阱本节最值钱)**

```bash
printf '9ms\n100ms\n' | awk '{ if ($1 > 50) print $1 }'
# 只输出 9ms —— 100ms 被静默漏掉了
```

`9ms` 不像纯数字，awk 按字典序比较，`'100ms' < '50'`。**不报错，只给错数字。**

**2. [Phase 4 · pipefail 为什么必需](04-shell.md#1-set-euopipefail-逐个实测)**

```bash
false | true; echo $?        # 0
set -o pipefail; false | true; echo $?   # 1
```

不加 pipefail，`grep ERROR log | sort | uniq -c` 在零匹配时会被判定成功 —— 「没找到错误」和「找到了错误」变成同一件事。

**3. [Phase 7 · namespace vs cgroups](07-internals.md#5-namespace--cgroups--docker-的真相)**

> namespace 给你一个"假的世界"，cgroups 决定这个假世界能吃多少资源。

---

## 实测结论速查

| 现象 | 真相 | 出处 |
|---|---|---|
| `ls` 一个文件要 178 次系统调用 | 动态链接 + 用户组查询 + 挂载点查询 | [07](07-internals.md) |
| 容器 `ExitCode: 0` 但服务被杀 | SIGKILL 杀的是应用，shell 正常退出。看 `OOMKilled` 字段 | [07](07-internals.md) |
| `df` 说满了，`du` 算不出多少 | 已删除但被进程持有的文件，`/proc/*/fd` 里能看到 | [03](03-permissions.md) |
| 本机能访问，局域网访问不了 | 服务绑了 `127.0.0.1`，或客户端走了代理 | [05](05-network.md) |
| `chmod go-w` 没反应 | 符号法是"移除"不是"设置" | [03](03-permissions.md) |
| 目录 `444` 能 `ls` 但不能 `cd` | `r` 给列名，`x` 给访问权 | [03](03-permissions.md) |
| 容器删了数据没了 | 正常行为，状态要放卷里 | [06](06-docker.md) |
| 镜像莫名 40MB 变大 | `apt-get update` 的 lists 没删 | [06](06-docker.md) |
| `sort -r` 把 9 排在 10 前面 | 缺 `-n`，走了字典序 | [01](01-filesystem.md) |
| 批量删文件误删 | `rm $*` 把 `"a b"` 拆成两个词 | [04](04-shell.md) |
| 备份能列出但解不开 | 中断留下半成品包，没做原子替换 | [04](04-shell.md) |

---

## 交付物清单

### 脚本（全部 `set -euo pipefail`，有参数校验，已过 CI）

| 脚本 | 功能 |
|---|---|
| [`01-stats.sh`](../scripts/01-stats.sh) | 日志统计分析：IP 频次、状态码、响应时间、慢请求 |
| [`03-disk-usage.sh`](../scripts/03-disk-usage.sh) | 目录空间占用 Top 20，含 df/du 交叉对比 |
| [`03-process-watch.sh`](../scripts/03-process-watch.sh) | 实时监控内存/负载/CPU Top 进程 |
| [`04-backup.sh`](../scripts/04-backup.sh) | 带保留策略和完整性校验的备份 |
| [`05-port-check.sh`](../scripts/05-port-check.sh) | 端口扫描，带超时和安全提示 |

### 实验产物

| 路径 | 内容 |
|---|---|
| [`labs/05-network/myapp.service`](../labs/05-network/myapp.service) | systemd unit 逐字段注释 |
| [`labs/06-docker/stats/`](../labs/06-docker/stats/) | 多阶段构建的 Dockerfile |
| [`labs/06-docker/docker-compose.yml`](../labs/06-docker/docker-compose.yml) | 服务名 DNS、健康检查依赖 |

### 数据

| 路径 | 内容 |
|---|---|
| [`data/logs/access.log`](../data/logs/access.log) | 10 行 Web 访问日志，awk/sed 练习素材 |
| [`data/playground/`](../data/playground/) | 目录树，含嵌套与大文件，find/du 练习素材 |

---

## 命令速查（按阶段）

<details>
<summary>Phase 1 · 文件系统与管道</summary>

```bash
pwd  cd  cd -  cd ~  ls -la
find . -type f -name "*.log"   -size +100k   -mtime -7
cat head tail less wc -l
grep -i -E -c -o -v -rn -A2 -B2 -C2
sort  -n  -rn       uniq -c
>  >>  |  2>  2>&1  $(...)  &&  ||  ;
*  ?  [a-z]  {a,b}  \  '...'  "..."
```
</details>

<details>
<summary>Phase 2 · 文本三剑客</summary>

```bash
grep -i     # 忽略大小写      sed 's/a/b/g'   # 替换
grep -E     # 正则            sed -i         # 原地
grep -c     # 计数            sed -i.bak     # 原地+备份
grep -o     # 只输出匹配部分   sed '/pat/d'   # 删行
grep -v     # 反选            sed -n '5,8p'  # 只打印 5-8 行

awk '{print $N}'            # 第 N 列
awk -F','                   # 自定义分隔符
awk '/pat/{...}'            # 条件处理
awk '{a[$1]++} END{}'       # 数组计数
awk '{s+=$1} END{print s}'  # 求和
$0   # 整行
$1+0 # 强制转数字 ⚠️
```
</details>

<details>
<summary>Phase 3 · 权限与进程</summary>

```bash
ls -l / ls -ld       chmod 755 / chmod u+x    chown user:group
umask                chmod 600 ~/.ssh/*
ps aux / ps -eo pid,ppid,pcpu,stat,comm --sort=-pcpu
top -bn1             kill PID / kill -9 PID / kill -l
jobs / fg %1 / bg %1    nohup cmd &    disown -h %1
free -h / df -h / du -sh / uptime -p
du -h --max-depth=1 ~ | sort -rh | head
find ~ -type f -printf '%s %p\n' | sort -rn | head
ls -l /proc/*/fd/ 2>/dev/null | grep deleted
```
</details>

<details>
<summary>Phase 4 · Shell 脚本</summary>

```bash
#!/usr/bin/env bash
set -euo pipefail          # -e 失败退出 -u 未定义退出 -o pipefail 管道任一失败
readonly X="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$1"   "$@"   $#   ${1:-default}   shift
[[ -f ]]  [[ -d ]]  [[ -z ]]  [[ =~ ^[0-9]+$ ]]
if/for/while/case          if cmd; then  # cmd 失败在 if 里豁免 -e
cmd || true                # 显式允许失败
trap cleanup EXIT          # 退出时清理
local x=$?                # 必须在函数第一行
date +%Y%m%d-%H%M%S
mapfile -t arr < <(cmd)    rm -f -- "$f"
tar -czf out.tar.gz -C /path dir/
```
</details>

<details>
<summary>Phase 5 · 网络与运维</summary>

```bash
ip -brief addr / ip route
ss -tlnp                    # 监听端口 + 进程
curl -sv / -I / --noproxy '*' -w '%{http_code} %{time_total}\n'
getent hosts / dig / ping -c 3 / nc -zv host port

ssh-keygen -t ed25519 -C "tag"
ssh -L local:remote:port host      # 本地转发
ssh -R local:remote:port host      # 远程转发
ssh -J bastion target              # 跳板
ssh -v host                        # 调试
scp -r / rsync -avz --dry-run       # 传输
chmod 600 ~/.ssh/config ~/.ssh/id_*

systemctl status/start/enable/disable/cat
systemctl enable --now xxx / daemon-reload
journalctl -u xxx -f / -p err / --since "1 hour ago"
```
</details>

<details>
<summary>Phase 6 · Docker</summary>

```bash
docker pull / build -t name:tag . 
docker run -d --name x -p 127.0.0.1:8080:80 -v vol:/data:ro img
docker ps -a / logs -f x / exec -it x sh / stop / rm
docker inspect x / stats / system df / system prune
docker builder prune -a
docker compose up -d / ps / logs -f / exec / down / down -v
docker compose config            # 验证语法
```

```dockerfile
FROM img:tag AS builder
RUN apt-get update && apt-get install -y --no-install-recommends pkg \
    && rm -rf /var/lib/apt/lists/*      # 必须合并成一条
COPY --chmod=755 f ./                    # 优于 RUN chmod
USER 10001:10001
ENTRYPOINT ["/app"]
```
</details>

<details>
<summary>Phase 7 · 系统原理</summary>

```bash
cat /proc/self/{cmdline,status,maps,limits}
ls -l /proc/self/fd/ /proc/self/cwd /proc/self/exe
ls -l /proc/*/fd/ 2>/dev/null | grep deleted
strace -c -f -e trace=openat cmd / strace -p PID
man 2 <syscall名>
dmesg | grep -i "killed process"
docker inspect x --format '{{.State.OOMKilled}}'
docker run --memory 100m --cpus 0.5 img
lsns -t pid / unshare --pid --fork --mount-proc bash
cat /proc/self/uid_map
```
</details>

---

## 学习方法

这份笔记的核心不是命令列表，是**每条结论背后的实测过程**。

每个非显然的结论都配了真实的 console 输出，包括：

- 失败的尝试（`sed` 改不了文件名、`go-w` 没反应、awk 静默漏判）
- 排查过程（curl 被代理截走、OOM 后 `ExitCode: 0` 的误导）
- 量化对比（185 倍 IO 差距、41MB 索引、178 次系统调用）

**运维工作里最贵的不是不会写，是"以为自己写对了"。** 这些实测的价值就在于排除这种可能。
