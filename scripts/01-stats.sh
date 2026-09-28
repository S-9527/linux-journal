#!/usr/bin/env bash
#
# 01-stats.sh — Web 访问日志统计分析
#
# 用法: ./01-stats.sh [日志文件]
# 默认: ../data/logs/access.log
#
# 演示 Unix 管道哲学: 每个命令只干一件事, 结果吐给下一个。
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG="${1:-$SCRIPT_DIR/../data/logs/access.log}"

if [[ ! -f "$LOG" ]]; then
    echo "错误: 找不到日志文件 $LOG" >&2
    exit 1
fi

section() {
    printf '\n\033[1;36m── %s\033[0m\n' "$1"
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ 1. 基础统计                                                      │
# └─────────────────────────────────────────────────────────────────┘
section "1. 基础统计"

printf '总行数:      %s\n' "$(wc -l < "$LOG")"
printf 'ERROR 行数:  %s\n' "$(grep -c ERROR "$LOG" || true)"
printf 'WARN 行数:   %s\n' "$(grep -c WARN "$LOG" || true)"

# ┌─────────────────────────────────────────────────────────────────┐
# │ 2. 错误最多的 IP                                                  │
# │                                                                 │
# │ 关键: 统计前必须 sort 让相同行相邻, uniq 只去相邻的重复          │
# └─────────────────────────────────────────────────────────────────┘
section "2. 错误最多的 IP (Top 5)"

grep ERROR "$LOG" \
    | awk '{print $4}' \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -5 \
    | awk '{printf "  %-16s %s 次\n", $2, $1}'

# ┌─────────────────────────────────────────────────────────────────┐
# │ 3. HTTP 状态码分布                                               │
# │                                                                 │
# │ 注意: 排序必须用 -n, 否则 "9" > "10" (字典序)                   │
# └─────────────────────────────────────────────────────────────────┘
section "3. HTTP 状态码分布"

awk '{print $7}' "$LOG" \
    | sort \
    | uniq -c \
    | sort -rn \
    | awk '{printf "  %-6s %s 次\n", $2, $1}'

# ┌─────────────────────────────────────────────────────────────────┐
# │ 4. 响应时间统计                                                  │
# │                                                                 │
# │ 12ms → gsub 去掉 ms → 当数字累加 → END 块输出一次                │
# └─────────────────────────────────────────────────────────────────┘
section "4. 响应时间统计"

awk '{
    gsub(/ms/, "", $8)        # "12ms" → "12"
    total += $8               # 累加
    count++
    if ($8 > max) max = $8
    if ($8 < min || min == 0) min = $8
}
END {
    if (count == 0) exit
    printf "  次数:    %d\n", count
    printf "  总计:    %dms\n", total
    printf "  平均:    %.1fms\n", total / count
    printf "  最慢:    %dms\n", max
    printf "  最快:    %dms\n", min
}' "$LOG"

# ┌─────────────────────────────────────────────────────────────────┐
# │ 5. 耗时最长的 5 个请求                                            │
# └─────────────────────────────────────────────────────────────────┘
section "5. 耗时最长的 5 个请求"

awk '{
    gsub(/ms/, "", $8)
    printf "%8dms  %s %s %s\n", $8, $4, $6, $7
}' "$LOG" | sort -rn | head -5

# ┌─────────────────────────────────────────────────────────────────┐
# │ 6. 错误行落盘                                                    │
# │                                                                 │
# │ 用 >> 追加而非 > 覆盖, 且每次运行前不主动清空:                   │
# │ 保留历史记录, 需要干净文件时由调用方 rm。                        │
# └─────────────────────────────────────────────────────────────────┘
section "6. 错误行落盘"

readonly OUT="$SCRIPT_DIR/../labs/01-filesystem/errors.txt"
mkdir -p "$(dirname "$OUT")"
grep ERROR "$LOG" >> "$OUT"
printf '  追加 %s 行 → %s\n' "$(grep -c ERROR "$LOG" || true)" "$OUT"
printf '  文件当前共 %s 行 (历史累积)\n' "$(wc -l < "$OUT")"

printf '\n\033[1;32m✓ 完成\033[0m\n'

# 临时: 故意失败
echo "intentional failure"
exit 1
