#!/usr/bin/env bash
# 容器内的入口脚本。故意写得精简 —— 只需要 shell 内建 + coreutils。
set -euo pipefail

case "${1:---help}" in
    --help|-h)
        cat <<EOF
linux-stats 1.0 — 日志统计工具

用法: stats.sh [选项]

选项:
  -h, --help      显示帮助
  -v, --version   显示版本

示例:
  docker run --rm linux-stats:1.0 --help
EOF
        ;;
    -v|--version)
        echo "linux-stats 1.0"
        ;;
    *)
        echo "未知参数: $1" >&2
        echo "试试 --help" >&2
        exit 1
        ;;
esac
