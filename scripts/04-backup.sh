#!/usr/bin/env bash
#
# 04-backup.sh — 带保留策略的目录备份
#
# 用法: ./04-backup.sh <源目录> <目标目录> [保留份数]
# 例:   ./04-backup.sh ~/data ~/backups 7
set -euo pipefail

readonly KEEP_DEFAULT=7

usage() {
    cat <<EOF
用法: $(basename "$0") <源目录> <目标目录> [保留份数]

  源目录      要备份的内容
  目标目录    备份包存放位置（自动创建）
  保留份数    保留最近几份，默认 ${KEEP_DEFAULT}

例:
  $(basename "$0") ~/data ~/backups
  $(basename "$0") ./src /tmp/bak 3
EOF
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ 退出时清理                                                       │
# │                                                                 │
# │ 无论正常结束、出错退出还是被 Ctrl+C，trap EXIT 都会执行            │
# │ 不加的话，Ctrl+C 中断会在目标目录留下半成品 .tar.gz               │
# └─────────────────────────────────────────────────────────────────┘
readonly TMP_PREFIX=".tmp-backup-"
cleanup() {
    local status=$?
    if [[ -n "${TMP_FILE:-}" && -f "$TMP_FILE" ]]; then
        rm -f "$TMP_FILE"
    fi
    return $status
}
trap cleanup EXIT

# ┌─────────────────────────────────────────────────────────────────┐
# │ 参数校验                                                         │
# └─────────────────────────────────────────────────────────────────┘
if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 1
fi

readonly SRC="$1"
readonly DEST="$2"
readonly KEEP="${3:-$KEEP_DEFAULT}"

if [[ ! -d "$SRC" ]]; then
    echo "错误: 源目录 '$SRC' 不存在" >&2
    exit 1
fi

if ! [[ "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
    echo "错误: 保留份数必须是正整数，收到 '$KEEP'" >&2
    exit 1
fi

# 源和目标不能是同一个目录，否则会把自己打进包里
if [[ "$(cd "$SRC" && pwd)" == "$(mkdir -p "$DEST" && cd "$DEST" && pwd)" ]]; then
    echo "错误: 源目录和目标目录不能相同" >&2
    exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ 备份名字用【目录名_时间戳】，不能只有时间戳                       │
# │ 否则多个源目录的备份混在一起，分不清哪个是哪个                    │
# └─────────────────────────────────────────────────────────────────┘
readonly SRC_NAME="$(basename "$(cd "$SRC" && pwd)")"
readonly STAMP="$(date +%Y%m%d-%H%M%S)"
readonly ARCHIVE_NAME="${SRC_NAME}_${STAMP}.tar.gz"
readonly ARCHIVE_PATH="$DEST/$ARCHIVE_NAME"
TMP_FILE="$DEST/${TMP_PREFIX}${ARCHIVE_NAME}"

mkdir -p "$DEST"

log() { printf '\033[1;36m▸\033[0m %s\n' "$1"; }
ok()  { printf '\033[1;32m✓\033[0m %s\n' "$1"; }

# ┌─────────────────────────────────────────────────────────────────┐
# │ 执行备份                                                         │
# │                                                                 │
# │ 先写临时文件，成功后再 mv —— 避免中断时留下被误认为有效的半个包    │
# └─────────────────────────────────────────────────────────────────┘
log "备份 $SRC → $DEST"

log "计算源目录大小..."
readonly SRC_SIZE="$(du -sh "$SRC" | cut -f1)"
log "  源目录大小: $SRC_SIZE"

log "创建压缩包 (可能需要一点时间)..."
# -C "$(dirname "$SRC")" 只打包目录本身，不带上完整路径前缀
tar -czf "$TMP_FILE" -C "$(dirname "$(cd "$SRC" && pwd)")" "$SRC_NAME"
ok "压缩完成"

# 校验压缩包完整性 —— 备份的最重要意义就是"出事时能用"
log "校验压缩包完整性..."
if ! tar -tzf "$TMP_FILE" > /dev/null; then
    echo "错误: 压缩包损坏，已清理" >&2
    exit 1
fi
ok "压缩包完整"

mv "$TMP_FILE" "$ARCHIVE_PATH"
TMP_FILE=""
readonly ARCHIVE_SIZE="$(du -h "$ARCHIVE_PATH" | cut -f1)"
ok "已保存 $ARCHIVE_NAME ($ARCHIVE_SIZE)"

# ┌─────────────────────────────────────────────────────────────────┐
# │ 清理旧备份                                                       │
# │                                                                 │
# │ ls -1t 按时间倒序 → tail -n +8 跳过前 7 个（最新的）              │
# │ → 剩下的都是要删的。xargs -r 在空输入时不执行 rm（GNU 扩展）      │
# │                                                                 │
# │ -a 而非管道给 rm：避免文件名以 - 开头被当成选项                    │
# └─────────────────────────────────────────────────────────────────┘
log "清理旧备份（保留最近 $KEEP 份）..."

mapfile -t OLD_BACKUPS < <(
    find "$DEST" -maxdepth 1 -name "${SRC_NAME}_*.tar.gz" -printf '%T@ %p\n' \
        | sort -rn \
        | tail -n "+$((KEEP + 1))" \
        | cut -d' ' -f2-
)

if [[ ${#OLD_BACKUPS[@]} -eq 0 ]]; then
    ok "无需清理（当前 $KEEP 份以内）"
else
    for old in "${OLD_BACKUPS[@]}"; do
        rm -f -- "$old"
        printf '  \033[1;33m-\033[0m 已删除 %s\n' "$(basename "$old")"
    done
    ok "已清理 ${#OLD_BACKUPS[@]} 份旧备份"
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ 汇总                                                             │
# └─────────────────────────────────────────────────────────────────┘
printf '\n\033[1;32m备份完成\033[0m\n'
printf '  目录:     %s\n' "$DEST"
printf '  当前份数: %s\n' "$(find "$DEST" -maxdepth 1 -name "${SRC_NAME}_*.tar.gz" | wc -l)"
printf '  总占用:   %s\n' "$(du -sh "$DEST" | cut -f1)"

printf '\n\033[1;32m当前保留的备份:\033[0m\n'
find "$DEST" -maxdepth 1 -name "${SRC_NAME}_*.tar.gz" -printf '%T@ %f %s\n' \
    | sort -rn \
    | cut -d' ' -f2- \
    | while read -r name size; do
        printf '  %-32s %s\n' "$name" "$(du -h "$DEST/$name" | cut -f1)"
    done
