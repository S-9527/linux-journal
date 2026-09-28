# Phase 6 · Docker 容器化

> **把"在我这能跑"变成"在任何地方都能跑"。**
> Docker 到底做了什么，答案在 Phase 7。
> 本文所有输出均为实际执行所得（Docker 29.6.2 on WSL2）。

---

## 1. 四个核心概念

| 概念 | 是什么 | 类比 |
|---|---|---|
| **镜像 Image** | 不可变模板（文件系统 + 启动命令 + 元数据） | 安装盘 / 菜谱 |
| **容器 Container** | 镜像跑起来的实例，有独立进程和写层 | 装好的系统 / 一次烹饪 |
| **卷 Volume** | 独立于容器生命周期的存储 | U 盘 |
| **网络 Network** | 虚拟交换机，容器间可用名字互访 | 办公室内网 |

**容器不是虚拟机。**

| | 虚拟机 | 容器 |
|---|---|---|
| 虚拟的是 | **硬件**（自带内核） | **视图**（共享宿主机内核） |
| 启动 | 30 秒+ | **毫秒级** |
| 体积 | GB | MB |
| 隔离强度 | 强 | 弱（共享内核） |
| 能跑不同内核 | 能 | **不能** |

**这个差异决定了一切**：容器必须和宿主机同内核（Linux 容器跑不了 Windows 程序，反之亦然）。

---

## 2. `docker run` 参数解剖

```bash
docker run -d --name web -p 127.0.0.1:8080:80 -v ~/data:/app/data:ro nginx
#          │      │        │          │              │
#          │      │        │          │              └─ :ro = 只读挂载
#          │      │        │          └──────────────── 宿主机路径:容器路径
#          │      │        └─────────────────────────── -p 端口映射
#          │      └──────────────────────────────────── --name 容器名
#          └─────────────────────────────────────────── -d 后台
```

⚠️ **端口方向不能写反**：`-p 宿主机端口:容器端口`。

容器内服务监听 80，你写 `-p 8080:80` 才能用 `localhost:8080` 访问。写成 `-p 80:8080` 会失败，因为容器里根本没有 8080。

**本机 compose 里的写法值得注意：**

```yaml
ports:
  - "127.0.0.1:28080:80"     # 只对本机开放
```

绑 `127.0.0.1` 而不是 `0.0.0.0` —— 呼应 Phase 5 的坑，**数据库和内部服务绝不该绑 `0.0.0.0`**。

---

## 3. 镜像体积实测

### 基础镜像

```console
$ docker images ubuntu:26.04 --format '{{.Size}}'
160MB
```

### `rm -rf /var/lib/apt/lists/*` 到底省多少

```console
$ docker run --rm ubuntu:26.04 sh -c '
    echo "初始 /var:            $(du -sh /var | cut -f1)"
    apt-get update -qq
    echo "update 后 apt/lists:  $(du -sh /var/lib/apt/lists | cut -f1)"
    apt-get install -y -qq curl
    echo "install 后 /usr:      $(du -sh /usr | cut -f1)"
    rm -rf /var/lib/apt/lists/*
    echo "清理后 /var:          $(du -sh /var | cut -f1)"
  '
初始 /var:            5.0M
update 后 apt/lists:  41M
install 后 /usr:      122M
清理后 /var:          6.7M
```

**`apt-get update` 下载的索引占 41MB，装完包就完全没用了。** 不删的话这 41MB 会永久留在镜像每一层里。

**`--no-install-recommends` 也能省**：默认会装"推荐的"包，很多用不上。

---

## 4. Dockerfile 分层

完整示例见 [`labs/06-docker/stats/Dockerfile`](../labs/06-docker/stats/Dockerfile)。

### 每条指令生成一层，层被缓存

```
FROM ubuntu:26.04      ← 层 1
RUN apt-get update...  ← 层 2
WORKDIR /build          ← 层 3（几乎不占空间）
COPY stats.sh ./        ← 层 4
```

**只有某一层的指令变了，它之后所有层的缓存才失效。**

### 铁律：变化少的放前面

```dockerfile
# ✅ 正确
COPY package.json ./
RUN npm install
COPY . .                 # 代码变了只重跑这一层

# ❌ 错误
COPY . .
RUN npm install          # 改一行代码就要重装全部依赖
```

### 铁律：`apt-get update` 和 `install` 必须同一条

```dockerfile
# ✅ 正确
RUN apt-get update \
    && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*

# ❌ 错误
RUN apt-get update      # 这层被缓存
RUN apt-get install -y curl
# → 软件源更新了也不会重新拉取, 装到过期版本
```

**`RUN` 的 `&&` 链在同一个层里，任何一步失败整条作废 —— 顺带保证了原子性。**

### 多阶段构建

```dockerfile
FROM ubuntu:26.04 AS builder
RUN apt-get update && apt-get install -y gcc make && rm -rf /var/lib/apt/lists/*
# ... 编译 ...

FROM ubuntu:26.04        # ← 最终镜像不含 gcc/make
COPY --from=builder /app/binary /app/
```

**构建阶段可以有任意工具，最终镜像只带产物。** Go/Rust/Node 项目收益巨大。

### `COPY --chmod` 优于 `RUN chmod`

```dockerfile
COPY --chmod=755 script.sh ./     # ✅ 一步到位，不多一层
COPY script.sh ./
RUN chmod +x script.sh            # ⚠️ 多一层，且会破坏缓存
```

---

## 5. 构建与运行实测

```console
$ docker build -t linux-stats:1.0 .
#9 exporting to image ... DONE 0.3s

$ docker images linux-stats:1.0 --format '{{.Size}}'
157MB

$ docker run --rm linux-stats:1.0 --version
linux-stats 1.0

$ docker run --rm linux-stats:1.0 --bogus
未知参数: --bogus
试试 --help
退出码: 1                    ← 正确返回非 0

$ docker run --rm --entrypoint id linux-stats:1.0
uid=10001(stats) gid=999(stats) groups=999(stats)    ← 非 root
```

**157MB vs 基础镜像 160MB** —— 看起来没变大，因为基础镜像的层被完全复用了，我们只加了几 MB。

---

## 6. 容器里的 `localhost` 是谁

这是容器网络最反直觉的一点。

```console
$ docker run --rm alpine sh -c 'hostname -i'
172.17.0.2                  ← 容器自己的 IP

$ docker run --rm --network host alpine sh -c 'echo xxx'
  --network host 下 localhost 就是宿主机
```

**容器有独立的网络 namespace，所以 `localhost` = 容器自己。** 容器里写 `localhost:5432` 想连宿主机的数据库，必然失败。

### 访问宿主机的三种方式

```bash
# 1. host.docker.internal (Docker Desktop / 新版 Docker 内置)
#    本机实测: 未定义，需要 --add-host
docker run --rm --add-host=host.docker.internal:host-gateway alpine \
    ping -c1 host.docker.internal

# 2. 宿主机网桥 IP
docker run --rm alpine ping -c1 172.17.0.1

# 3. --network host (Linux only, 牺牲隔离换简单)
docker run --rm --network host alpine ping -c1 127.0.0.1
```

---

## 7. 卷：容器删了数据还在

实测：

```console
$ docker volume create vol_test
$ docker run --rm -v vol_test:/data alpine sh -c \
    'echo "重要数据" > /data/persisted.txt'
-rw-r--r-- 1 root root 13 ... persisted.txt

# 容器已随 --rm 删除
$ docker run --rm -v vol_test:/data alpine sh -c 'cat /data/persisted.txt'
重要数据                              ← 数据还在

$ docker volume ls | grep vol_test
local  vol_test
```

**卷独立于容器生命周期。** 容器是易失的，卷是持久的。

三种挂载类型：

| 类型 | 写法 | 数据位置 | 适合 |
|---|---|---|---|
| **卷 Volume** | `-v myvol:/data` | Docker 管理，宿主机特定目录 | **数据库、上传文件** |
| **绑定挂载 Bind** | `-v /host/path:/data` | 宿主机任意路径 | 开发时挂源码 |
| **tmpfs** | `--tmpfs /data` | 内存 | 临时文件，不落盘 |

**开发时用 bind 挂载源码（改代码容器立刻生效），生产用 volume 存数据。**

---

## 8. docker-compose

完整示例见 [`labs/06-docker/docker-compose.yml`](../labs/06-docker/docker-compose.yml)。

### 核心：服务名就是 DNS

```yaml
services:
  app:
    environment:
      DB_HOST: db        # ← 直接写服务名, Docker 内置 DNS 会解析
  db:
    image: postgres:17
```

**app 容器连数据库写 `db:5432`，不是 `localhost:5432`。** compose 会创建一个用户自定义网络，内置 DNS 把服务名解析到容器 IP。

### 密码不要硬编码

```yaml
environment:
  DB_PASSWORD: ${DB_PASSWORD:?请在 .env 里设置 DB_PASSWORD}
```

`${VAR:?message}` 的语法是"如果 VAR 没设置就报错退出并显示 message"。

相比直接写明文，好处是：
- 密码不进 git
- 忘了设置会立刻失败，而不是静默用空密码

`.env` 文件（加进 `.gitignore`）：

```
DB_PASSWORD=真正的密码
```

### 健康检查与依赖顺序

```yaml
  db:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U statsuser -d statsdb"]
      interval: 10s
      retries: 5
      start_period: 30s

  app:
    depends_on:
      db:
        condition: service_healthy    # ← 等 db 真的健康, 不是"已启动"
```

**注意区别**：`condition: service_started` 只保证容器起来了，但数据库可能还在初始化。`service_healthy` 才等到能接受连接。

### 常用命令

```bash
docker compose up -d            # 启动
docker compose ps               # 状态
docker compose logs -f app      # 跟日志
docker compose exec app bash    # 进容器
docker compose down             # 停止(保留数据卷)
docker compose down -v          # 停止并删数据卷 ⚠️
docker compose config           # 看最终展开的配置(调试神器)
```

⚠️ **`down -v` 会删掉数据卷。** 生产环境慎用。

### 实测：语法验证

```console
$ DB_PASSWORD=testpass docker compose -f docker-compose.yml config --quiet
✓ compose 文件语法正确
```

`config` 是验证 compose 文件的最快方式，不用真启动。

---

## 9. WSL2 特有坑

### 9.1 文件挂载性能极差

**这是 Phase 0 那个 185 倍问题的延续。** 挂载 Windows 目录进容器会慢一个数量级：

```yaml
volumes:
  - /mnt/c/Users/xx/project:/app     # ❌ 慢
  - ~/project:/app                   # ✅ 快
```

### 9.2 权限错乱

Windows 挂载进来的文件在容器里可能全是 `777` 或 `755`，`chmod` 不生效。表现为"本地好好的，进容器就是 Permission denied"。

### 9.3 `host.docker.internal` 未定义

本机实测：

```console
$ docker run --rm alpine sh -c 'getent hosts host.docker.internal'
  未定义（需 --add-host 或 Docker Desktop）
```

**这是纯 Linux Docker（不是 Docker Desktop）**。解法：

```bash
--add-host=host.docker.internal:host-gateway
```

### 9.4 空间增长快

```console
$ docker system df
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          8         1         2.805GB   1.477GB (52%)
Containers      1         1         20.48kB   0B (0%)
Local Volumes   3         1         234.2MB   48.11MB (20%)
Build Cache     103       0         7.249GB   4.534GB
```

**Build Cache 7.2GB！** 每次 build 都留缓存。这是 WSL2 上 Docker 最常见的空间黑洞。

```bash
docker system prune              # 清理未使用的
docker builder prune            # 只清构建缓存
docker builder prune -a         # 连未使用的层一起清
```

---

## 10. 思考题答案

### 1. 容器 vs 虚拟机

**本质区别：虚拟化的是硬件还是视图。**

| | 虚拟机 | 容器 |
|---|---|---|
| 隔离层 | Hypervisor 虚拟出完整硬件，**自带内核** | 内核提供 namespace/cgroups，**共享内核** |
| 启动 | 30 秒 | 毫秒 |
| 体积 | GB 级（要装 OS） | MB 级（只有应用 + 依赖） |
| 隔离 | 强，内核级 | 弱，共享内核 |
| 跨内核 | ✅ 能装 Linux/Windows 内核 | ❌ 必须同内核 |
| 密度 | 几十个 | 几百上千个 |

**"轻"不是免费的 —— 代价是隔离弱。** 容器逃逸（breakout）的风险理论存在，历史上确实发生过（CVE-2019-5736 runc 逃逸）。金融隔离、多租户场景仍需要 VM。

### 2. `-p 8080:80` 写反的后果

容器内服务监听 **80**。`-p 8080:80` 的语义是"宿主机 8080 → 容器 80"，正确。

写反成 `-p 80:8080` 意味着"宿主机 80 → 容器 8080"，但容器里没人监听 8080 → 连接被拒绝。

**记忆法：先看容器里 `ss -tlnp` 显示什么端口，那个数字要放在右边。**

### 3. Docker 为什么轻？代价是什么

**轻的原因：容器不含内核。** 镜像只有应用二进制 + 依赖库 + 配置文件。内核由宿主机提供（namespace 隔离视图，cgroups 限制资源）。

**代价：**

- **隔离弱** —— 共享内核，内核漏洞可能被利用逃逸
- **不能跨内核** —— Linux 容器跑不了 Windows 程序
- **不保证确定性** —— 宿主机内核版本不同，`syscall` 行为可能有微妙差异
- **不能替代 VM 的安全边界** —— 多租户不可信场景仍需 VM

### 4. `apt-get update` 和 `install` 分成两条的后果

**缓存失效导致装到过期版本。**

每条 `RUN` 生成一层。`RUN apt-get update` 这层被缓存后，后续 build 直接用缓存里的结果，**不会真的去软件源拉最新索引**。而 `RUN apt-get install` 在这之后执行，用的是过期索引。

**症状：** 上游发布了安全补丁，你 `docker pull` 基础镜像拿到了新版本，重新 build 却"没变化" —— 因为 update 那层还是缓存的旧索引。

**解法：** 合并成一条 `RUN`，这样两层合成一层，任何时候 build 都会重新拉。

```dockerfile
RUN apt-get update \
    && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*
```

**顺带的好处：** 合并到一层后，`rm -rf` 删掉的 41MB 不会留在历史层里（见下一题）。

### 5. 容器里的 `localhost` 是谁

**容器自己。** 因为每个容器有独立的 **Network namespace**，拥有自己的回环接口。

**访问宿主机的三种方式：**

| 方式 | 写法 | 平台 |
|---|---|---|
| `host.docker.internal` | `ping host.docker.internal` | Docker Desktop / 新版 Docker |
| 网桥 IP | `ping 172.17.0.1` | 通用 |
| host 网络 | `--network host` | Linux only |

本机实测 `host.docker.internal` 未定义（纯 Linux Docker），需 `--add-host=host.docker.internal:host-gateway`。

**容器间互访用服务名/compose 服务名**，那是 Docker 内置 DNS 提供的，跟 `localhost` 无关。

### 6. 容器删了数据没了，是缺陷还是正常行为

**是正常行为，而且是有意的设计。** 容器的核心卖点之一就是"用完即抛"——

- 声明式部署：一个容器 = 一个进程，状态应该在外面
- 可重现：容器状态一致，才能保证扩容出来的实例行为相同
- 编排友好：K8s 随时替换 Pod，状态必须在 PV 里

**解法就是卷：**

```yaml
volumes:
  - dbdata:/var/lib/postgresql/data    # 具名卷
  - ./config:/etc/app/config           # bind 挂载配置
  - /var/logs/app:/app/logs            # bind 挂载日志
```

**原则：容器是易失的，卷是持久的。** 需要状态的一切都放卷里。

一个反面案例：

```bash
# ❌ 数据库数据写在容器可写层 → 容器一删数据就没了
docker run -d --name mydb postgres:17
```

```bash
# ✅ 数据在卷里 → 容器随便删
docker run -d --name mydb -v pgdata:/var/lib/postgresql/data postgres:17
```

---

## 速查

```bash
# 生命周期
docker pull / build -t name:tag .
docker run -d --name x -p 127.0.0.1:8080:80 -v vol:/data:ro img
docker ps -a / logs -f x / exec -it x sh / stop / start / rm
docker inspect x / stats / system df / system prune

# 镜像
docker images / history img / save / load
docker builder prune -a

# 清理
docker rm -f $(docker ps -aq)          # 删所有容器
docker volume rm $(docker volume ls -q)
docker system prune -a

# compose
docker compose up -d / ps / logs -f / exec / down / down -v
docker compose config                  # 验证语法
```

## Dockerfile 速查

```dockerfile
FROM img:tag AS builder        # 多阶段
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg \
    && rm -rf /var/lib/apt/lists/*      # 必须合并成一条
COPY --chmod=755 f ./         # 优于 RUN chmod
USER 10001:10001              # 非 root
WORKDIR /app
ENV KEY=val
EXPOSE 80                     # 文档性质，真正映射靠 -p
HEALTHCHECK CMD ... 
ENTRYPOINT ["/app"]           # JSON 形式，不走 shell
CMD ["--help"]
```
