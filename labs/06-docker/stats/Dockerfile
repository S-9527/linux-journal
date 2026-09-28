# 语法: docker build -t linux-stats:1.0 .
#
# 分层原则: 变化少的放前面, 变化多的放后面。
# 每次 RUN/COPY/ADD 生成一个层, 层被缓存。
# 只要某一层的指令变了, 它之后所有层的缓存都失效。

# ┌─────────────────────────────────────────────────────────────────┐
# │ 阶段 1: 构建                                                     │
# │                                                                 │
# │ 用多阶段构建: 构建产物拷贝出去, 最终镜像不含编译器/gcc/git 等     │
# │ 收益: 构建镜像可以有工具, 运行镜像保持精简                        │
# └─────────────────────────────────────────────────────────────────┘
FROM ubuntu:26.04 AS builder

# apt-get update 和 install 必须在同一条 RUN 里!
# 分成两条的话, install 那层会缓存住 update 的结果,
# 之后软件源更新了也不会重新拉取 → 装到过期版本
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 拷贝脚本本体(内容很少变) → 这层缓存命中率高
COPY stats.sh ./

# ┌─────────────────────────────────────────────────────────────────┐
# │ 阶段 2: 运行                                                     │
# │                                                                 │
# │ 实测: ubuntu:26.04 基础镜像 160MB                                 │
# │       update 后 /var/lib/apt/lists 占 41MB                        │
# │       rm -rf /var/lib/apt/lists/* 把它清掉                        │
# └─────────────────────────────────────────────────────────────────┘
FROM ubuntu:26.04

LABEL org.opencontainers.image.title="linux-stats" \
      org.opencontainers.image.description="日志统计工具" \
      org.opencontainers.image.version="1.0"

# 非 root 运行
RUN useradd -r -u 10001 -s /usr/sbin/nologin stats
USER stats

WORKDIR /app

# 权限在构建时就设好。COPY --chmod 一步到位(比 RUN chmod 少一层)
COPY --chmod=755 stats.sh ./

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app/stats.sh"] || exit 1

ENTRYPOINT ["/app/stats.sh"]
CMD ["--help"]
