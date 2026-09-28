#!/usr/bin/env bash
#
# 05-port-check.sh — 扫描目标主机常用端口，报告开放状态
#
# 用法: ./05-port-check.sh [主机] [超时秒数]
# 例:   ./05-port-check.sh 127.0.0.1 2
set -euo pipefail

readonly TIMEOUT_DEFAULT=2

# 常用端口清单
readonly PORTS=(
    22    # SSH
    80    # HTTP
    443   # HTTPS
    3000  # 常见开发服务
    5432  # PostgreSQL
    3306  # MySQL
    6379  # Redis
    8080  # 常见备用 HTTP
    27017 # MongoDB
)

usage() {
    cat <<EOF
用法: $(basename "$0") [主机] [超时秒数]

  主机      目标 IP 或域名，默认 127.0.0.1
  超时      单个端口的等待秒数，默认 ${TIMEOUT_DEFAULT}

例:
  $(basename "$0")
  $(basename "$0") 192.168.1.1 1
  $(basename "$0") github.com 3
EOF
}

HOST="${1:-127.0.0.1}"
TIMEOUT="${2:-$TIMEOUT_DEFAULT}"

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -eq 0 ]]; then
    echo "错误: 超时必须是正整数秒" >&2
    exit 1
fi

# 关键: 超时必须设置，否则在不存在的地址上会等 TCP 默认重传时间
# (Linux 上通常 2 分钟)，一个端口就够脚本卡死。
if ! command -v nc > /dev/null; then
    echo "错误: 需要 nc (netcat)，请先安装: sudo apt install netcat-openbsd" >&2
    exit 1
fi

# 描述表
declare -A DESC=(
    [22]="SSH"            [80]="HTTP"         [443]="HTTPS"
    [3000]="dev"          [5432]="PostgreSQL" [3306]="MySQL"
    [6379]="Redis"        [8080]="alt-HTTP"    [27017]="MongoDB"
)

printf '\033[1;36m▶ 扫描 %s\033[0m (超时 %ss)\n\n' "$HOST" "$TIMEOUT"
printf '  %-8s %-12s %-10s %s\n' "端口" "服务" "状态" "耗时"
printf '  %-8s %-12s %-10s %s\n' "----" "----" "----" "----"

open_count=0
closed_count=0

for port in "${PORTS[@]}"; do
    start=$(date +%s%N)

    # -z: 成功后发零字节并立即断开。-w: 超时。-n: 不做 DNS/协议预检
    if nc -z -w "$TIMEOUT" -n "$HOST" "$port" 2> /dev/null; then
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        printf '  \033[1;32m%-8s\033[0m %-12s \033[1;32m%-10s\033[0m %sms\n' \
            "$port" "${DESC[$port]:-?}" "开放" "$ms"
        open_count=$((open_count + 1))
    else
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        # 区分"关闭"和"被过滤"意义不大，这里统一显示为关闭
        printf '  %-8s %-12s %-10s %sms\n' \
            "$port" "${DESC[$port]:-?}" "关闭" "$ms"
        closed_count=$((closed_count + 1))
    fi
done

printf '\n\033[1;33m汇总\033[0m  开放 %s / 关闭 %s (共 %s)\n\n' \
    "$open_count" "$closed_count" "$((open_count + closed_count))"

if [[ $open_count -gt 0 ]]; then
    printf '\033[1;33m⚠  开放的服务中，确认都是有意暴露的。\033[0m\n'
    printf '\033[1;33m   数据库(3306/5432/6379/27017)不应该对公网开放。\033[0m\n\n'
fi
