#!/usr/bin/env bash
#
# 03-disk-usage.sh — 找出目录里空间占用最大的子目录
#
# 用法: ./03-disk-usage.sh [目录] [数量]
# 例:   ./03-disk-usage.sh ~/workspace 10
set -euo pipefail

readonly MAX_DEPTH_DEFAULT=2

usage() {
    cat <<EOF
用法: $(basename "$0") [目录] [深度]

  目录   要扫描的路径，默认当前目录
  深度   显示几层，默认 ${MAX_DEPTH_DEFAULT}

例:
  $(basename "$0") ~/workspace 2
  $(basename "$0") /var/log 1
EOF
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ 参数校验                                                          │
# │                                                                 │
# │ 注意 -u 的作用: 未定义变量会直接报错, 而 -z 检查空字符串          │
# └─────────────────────────────────────────────────────────────────┘
if [[ $# -gt 2 ]]; then
    usage >&2
    exit 1
fi

DIR="${1:-.}"
DEPTH="${2:-$MAX_DEPTH_DEFAULT}"

if [[ ! -d "$DIR" ]]; then
    echo "错误: '$DIR' 不是目录" >&2
    exit 1
fi

if ! [[ "$DEPTH" =~ ^[0-9]+$ ]]; then
    echo "错误: 深度必须是正整数，收到 '$DEPTH'" >&2
    exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ 核心实现                                                          │
# │                                                                 │
# │ du --max-depth=N : 逐层累加, 目录自身 + 下 N 层                 │
# │ sort -rh          : 按人类可读大小倒序 (h = 1K/2M/3G)            │
# │ head              : 取前 N 个                                    │
# │ awk               : 数字对齐输出                                 │
# └─────────────────────────────────────────────────────────────────┘
printf '\033[1;36m▶ %s\033[0m 目录下空间占用 Top 20（深度 %s）\n\n' "$DIR" "$DEPTH"

du -h --max-depth="$DEPTH" "$DIR" 2>/dev/null \
    | sort -rh \
    | head -20 \
    | awk '{
        size = $1
        $1 = ""
        sub(/^[[:space:]]+/, "")
        printf "  %8s  %s\n", size, $0
    }'

printf '\n\033[1;33m💡 总占用: \033[0m'
du -sh "$DIR" 2>/dev/null | cut -f1

printf '\033[1;33m💡 文件系统剩余: \033[0m'
df -h "$DIR" 2>/dev/null | awk 'NR==2 {print $4 " 可用 / " $2 " (" $5 " 已用)"}'

printf '\n'
