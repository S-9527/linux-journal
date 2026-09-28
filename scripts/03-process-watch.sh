#!/usr/bin/env bash
#
# 03-process-watch.sh — 实时监控内存与负载
#
# 用法: ./03-process-watch.sh [间隔秒数]
# 停止: Ctrl+C
set -euo pipefail

INTERVAL="${1:-2}"

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -eq 0 ]]; then
    echo "错误: 间隔必须是正整数秒" >&2
    exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ trap EXIT: 无论怎么退出都清理光标                                  │
# │ 不加的话, Ctrl+C 后终端会残留隐藏光标, 提示符消失                  │
# └─────────────────────────────────────────────────────────────────┘
readonly HIDE_CURSOR='\033[?25l'
readonly SHOW_CURSOR='\033[?25h'
readonly CLEAR='\033[H\033[2J'

cleanup() {
    printf "$SHOW_CURSOR"
    printf '\n\033[1;33m监控已停止\033[0m\n'
}
trap cleanup EXIT

printf "$HIDE_CURSOR"

while true; do
    printf "$CLEAR"
    printf '\033[1;36m═══ 系统监控 ═══\033[0m  %s  (每 %ss 更新, Ctrl+C 退出)\n\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$INTERVAL"

    # 内存: 从 /proc/meminfo 取, 比 free 更好解析
    mem_total=$(awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo)
    mem_avail=$(awk '/MemAvailable/ {printf "%.1f", $2/1048576}' /proc/meminfo)
    mem_used=$(awk -v t="$mem_total" -v a="$mem_avail" 'BEGIN {printf "%.1f", t - a}')

    printf '\033[1;33m内存\033[0m  总 %sG | 可用 %sG | 已用 %sG (%.0f%%)\n' \
        "$mem_total" "$mem_avail" "$mem_used" \
        "$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN {print u/t*100}')"

    # Swap
    swap_total=$(awk '/SwapTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo)
    swap_free=$(awk '/SwapFree/ {printf "%.1f", $2/1048576}' /proc/meminfo)
    printf '       Swap %sG | 可用 %sG\n' "$swap_total" "$swap_free"

    # 负载: /proc/loadavg 前三个数是 1/5/15 分钟
    read -r l1 l5 l15 _ < /proc/loadavg
    printf '\033[1;33m负载\033[0m  1min %s | 5min %s | 15min %s\n' "$l1" "$l5" "$l15"

    # 运行时长
    printf '\033[1;33m运行\033[0m  %s\n' "$(uptime -p)"

    # CPU 占用最高的 5 个进程
    printf '\n\033[1;33mCPU Top 5\033[0m\n'
    ps -eo pcpu,pmem,comm --sort=-pcpu 2>/dev/null \
        | head -6 \
        | awk 'NR==1 {printf "  %6s %6s %s\n", "CPU%", "MEM%", "COMMAND"; next}
               {printf "  %6s %6s %s\n", $1, $2, $3}'

    # 内存占用最高的 5 个进程
    printf '\n\033[1;33m内存 Top 5\033[0m\n'
    ps -eo pcpu,pmem,comm --sort=-pmem 2>/dev/null \
        | head -6 \
        | awk 'NR==1 {printf "  %6s %6s %s\n", "CPU%", "MEM%", "COMMAND"; next}
               {printf "  %6s %6s %s\n", $1, $2, $3}'

    sleep "$INTERVAL"
done
