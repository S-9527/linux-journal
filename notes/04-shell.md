# Phase 4 · Shell 脚本与第一条 CI

> **GitHub Actions 就是一台临时借给你的 Linux 机器。**
> 本文所有输出均为实际执行所得。

---

## 核心认知

Phase 1-3 学的所有东西在这一阶段**接通**了。

`ci.yml` 里那些看起来神秘的 YAML，其实就是你在 `labs/` 里跑过的命令，只不过被 `run: |` 包起来，换到云端的 Ubuntu 上执行。

```yaml
- name: 运行日志统计脚本
  run: ./scripts/01-stats.sh      # ← 和本地敲的一模一样
```

**CI 不是"另一种东西"，它就是远程 Linux。** 理解了这一点，`.github/workflows` 就从玄学变成了你在 Phase 1 练过的东西的另一种包装。

---

## 1. `set -euo pipefail` 逐个实测

### `-e`：命令失败就退出

```console
$ cat t1.sh
set -e
echo "1. 正常执行"
false
echo "2. 这一行不会打印，因为 false 失败了"

$ ./t1.sh
1. 正常执行
退出码: 1
```

**为什么重要：** 没有 `-e` 时，脚本会带着错误继续往下跑。前三步失败、第四步拿空数据算出"一切正常" —— 这种 bug 极难排查。

### `-u`：用了未定义变量就退出

```console
$ cat t2.sh
set -u
echo "开始"
echo "未定义变量是: $UNDEFINED_VAR"
echo "这行也不会打印"

$ ./t2.sh
开始
./t2.sh: 3: UNDEFINED_VAR: parameter not set
退出码: 2
```

**为什么重要：** 变量名打错（比如 `$FILENAME` 写成 `$FILENAM`）时，没有 `-u` 你拿到的是空字符串，脚本继续跑，产出一个看起来正常的错误结果。

### `-o pipefail`：管道里任一环失败就算失败

这是最容易被忽略的一个。实测：

```console
$ bash -c 'false | true; echo "无 pipefail 退出码: $?"'
无 pipefail 退出码: 0        ← 明明 false 失败了，却报成功

$ bash -c 'set -o pipefail; false | true; echo "有 pipefail 退出码: $?"'
有 pipefail 退出码: 1        ← 正确
```

**默认情况下管道的退出码只取最后一个命令。** 所以：

```bash
# 危险：grep 没找到（失败）但 sort|uniq 成功，整条管道被判定为成功
if grep ERROR app.log | sort | uniq -c; then
    echo "检查通过"
fi
```

没有 `pipefail` 时，即使一条 ERROR 都没有，这个 `if` 也会走 true 分支 —— **"没找到错误"和"找到了错误"变成了同一件事**。加 `pipefail` 后才区分得开。

---

## 2. `set -e` 的局限（重要）

**`set -e` 不是"任何失败都退出"。** 有一批位置是**豁免**的：

```console
$ cat e4.sh
set -e
if grep -q NOPE file.txt; then echo "找到"; else echo "  走 else 分支"; fi
echo "b: 继续执行"

$ ./e4.sh
  走 else 分支，正常
b: 继续执行
退出码: 0
```

**豁免位置**：`if` / `while` / `until` 的条件部分、`&&` 和 `||` 的左侧、`!` 取反。

### 真正会坑你的地方：命令替换

```console
$ cat e3.sh
set -e
count=$(grep -c ERROR file.txt)
echo "找到 $count 个"

$ ./e3.sh          # 文件里没有 ERROR
退出码: 1           # 整个脚本被踢出，echo 都没执行
```

**`$(...)` 内部的失败会传播到外层，触发 `set -e`。** 而 `grep -c` 在"零匹配"时返回 1 —— 那是**有效结果**，不是错误。

解法：

```console
$ cat e5.sh
set -e
count=$(grep -c ERROR file.txt || true)
echo "count = $count  (0 是有效结果，不是错误)"

$ ./e5.sh
count = 0  (0 是有效结果，不是错误)
退出码: 0
```

**`|| true` 的语义是"我明确知道这里可能失败，且失败是预期内的"。**

这条规则在 Phase 1 的 `01-stats.sh` 里已经用到了：

```bash
printf 'ERROR 行数:  %s\n' "$(grep -c ERROR "$LOG" || true)"
```

---

## 3. `"$@"` vs `"$*"`（能救命的区别）

实测：

```console
$ ./args.sh "file one" "file two"
参数个数 ($#): 2
  $@ 元素: [file one]        ← 保持为两个独立参数
  $@ 元素: [file two]
  $* 元素: [file one file two]   ← 用 IFS 拼成一个字符串
  IFS 拼接后 [$*]: [file one file two]
```

**区别：**

| | 行为 | 安全性 |
|---|---|---|
| `"$@"` | 保持参数边界，每个参数独立 | ✅ 安全 |
| `"$*"` | 用 IFS（默认空格）拼成单个字符串 | ⚠️ 危险 |
| `$@`（无引号） | 拆词 + 通配符展开 | ❌ 极危险 |

### 危险场景

```console
$ ./danger.sh "a b" "c"
危险写法 rm $*  → 展开成: rm a b c
```

**本意是删两个文件**（`"a b"` 和 `"c"`），**实际删了三个**（`a`、`b`、`c`）—— 因为 `"a b"` 里的空格被拆开了。

**铁律：遍历位置参数一律写 `"$@"`。**

```bash
# 正确
for arg in "$@"; do
    rm -- "$arg"
done

# 正确（数组形式，可选）
args=("$@")
rm -- "${args[@]}"
```

顺带一提：`rm -- "$arg"` 里的 `--` 是必须的，否则文件名以 `-` 开头（比如 `-rf`）会被 `rm` 当成选项。

---

## 4. 参数校验

```bash
if ! [[ "$DEPTH" =~ ^[0-9]+$ ]]; then
    echo "错误: 深度必须是正整数，收到 '$DEPTH'" >&2
    exit 1
fi
```

两个细节：

**`2>&1`（这里写成 `>&2`）—— 错误信息走 stderr。** 这样 `./script.sh 2>/dev/null` 能静音错误但保留正常输出，也方便 `cmd || echo "失败"` 捕获。

**`exit 1` 而不是 `exit 0`** —— 退出码非 0 才能被 CI 捕获到失败。

### 为什么用正则而不是 `-gt`

```bash
[[ "$x" =~ ^[0-9]+$ ]]     # ✅ 非数字 → 优雅报错
[ "$x" -gt 0 ]             # ⚠️ 非数字 → bash 自己报错，报错信息很难看
```

---

## 5. `trap ... EXIT`

```bash
TMP_FILE="$DEST/.tmp-backup-$ARCHIVE_NAME"

cleanup() {
    local status=$?
    if [[ -n "${TMP_FILE:-}" && -f "$TMP_FILE" ]]; then
        rm -f "$TMP_FILE"
    fi
    return $status
}
trap cleanup EXIT
```

**解决的问题：** 无论怎么退出（正常结束、某步失败、Ctrl+C），都清理临时文件。

**`${TMP_FILE:-}` 的 `:-` 语法不能省** —— 如果 `TMP_FILE` 从未被赋值，普通 `$TMP_FILE` 在 `set -u` 下会直接终止脚本，**而这正好发生在最需要 cleanup 的时刻**。`${TMP_FILE:-}` 表示"未定义就用空串"。

**`local status=$?` 要写在函数第一行** —— 捕获退出码必须在任何其他命令之前，否则 `$?` 已经被覆盖了。

### 为什么备份要"先写临时文件再 mv"

```bash
tar -czf "$TMP_FILE" ...      # 写到 .tmp-backup-xxx
tar -tzf "$TMP_FILE"          # 校验
mv "$TMP_FILE" "$ARCHIVE_PATH" # 成功后才改名
```

**避免中断时留下一个"看起来有效、实际损坏"的备份。** 运维脚本的核心原则：**宁可没有备份，不能有假备份** —— 后者会让你在真正需要恢复时才发现问题。

---

## 6. 保留策略

```bash
mapfile -t OLD_BACKUPS < <(
    find "$DEST" -maxdepth 1 -name "${SRC_NAME}_*.tar.gz" -printf '%T@ %p\n' \
        | sort -rn \
        | tail -n "+$((KEEP + 1))" \
        | cut -d' ' -f2-
)

for old in "${OLD_BACKUPS[@]}"; do
    rm -f -- "$old"
done
```

**逐步拆解：**

1. `find -printf '%T@ %p\n'` —— 输出 `修改时间戳 路径`
2. `sort -rn` —— 按时间倒序（最新的在前）
3. `tail -n "+8"` —— 跳过前 7 行（KEEP=7），**剩下的就是要删的**
4. `cut -d' ' -f2-` —— 去掉时间戳，只留路径
5. `mapfile -t` —— 读成 bash 数组，**`-t` 去掉行尾换行符**
6. `rm -f --` —— `-f` 不报错，`--` 防止路径以 `-` 开头

### 保留策略实测（KEEP=3，连跑 9 次）

```console
$ ./scripts/04-backup.sh /tmp/srcdemo /tmp/bak3 3   # ×9
✓ 无需清理（当前 3 份以内）      ×3
✓ 已清理 1 份旧备份              ×6

$ ls -1 /tmp/bak3
srcdemo_20260928-125103.tar.gz
srcdemo_20260928-125104.tar.gz
srcdemo_20260928-125106.tar.gz
份数: 3
```

**始终稳定在 3 份。** 注意文件名带时间戳 —— 时间戳必须在**秒级**且跑得够快时才有区分度，所以实测中间加了 `sleep 1.1`。

---

## 7. 第一条 CI workflow

完整内容见 [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)。

### 核心结构

```yaml
on:
  push:
    branches: [main]      # 推 main 时跑
  pull_request:
    branches: [main]      # PR 到 main 时跑

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4      # 特殊步骤: 把代码拉到 runner 上
      - run: ./scripts/01-stats.sh     # 普通步骤: 跑命令
```

**`runs-on: ubuntu-latest` 就是"选择一台云端 Linux 机器"。** Ubuntu 版本和你本地不一样，glob 和 `sed` 的实现可能不同 —— 这正是要在 CI 里跑一遍的原因。

### 一个真实的坑：执行权限

**git 里存的是文件的模式位。** 如果你本地 `chmod +x` 过，git 会记录 `100755`；没加就是 `100644`。CI checkout 出来会忠实还原。

但如果你忘了 `chmod +x`，CI 会报 `Permission denied`。两种解法：

```yaml
# 方案 A: CI 里补一刀（简单，推荐新手用）
- name: 赋予执行权限
  run: chmod +x scripts/*.sh
```

```bash
# 方案 B: 在 git 里强制记录（更干净）
git update-index --chmod=+x scripts/04-backup.sh
git commit -m "chore: 标记为可执行"
```

### 故意让 CI 失败一次（必须验证）

**必须确认 CI 能变红，否则你不知道它是否真的在检查。**

```bash
# 临时制造失败
echo "exit 1" >> scripts/01-stats.sh
git commit -am "test: 故意失败"
git push
gh pr checks --watch     # 观察变红
```

确认变红后 `git revert` 掉。

---

## 8. `readonly VAR="$(cmd)"` 会掩盖退出码

这是写 CI 时 shellcheck 实际报出来的坑。写法上看似严谨，实际上**破坏了 `set -e`**。

```console
$ cat sc_demo.sh
set -e
readonly BAD="$(cd /nonexistent && pwd)"
echo "这行照常打印 → 说明 set -e 失效了"

$ ./sc_demo.sh
sc_demo.sh: line 4: cd: /nonexistent: No such file or directory
这行照常打印 → 说明 set -e 失效了
退出码: 0                    ← 明明失败了，退出码却是 0
```

**原因：** bash 执行 `readonly BAD="$(cmd)"` 时，是先把 `$(cmd)` 的输出**作为参数**交给 `readonly`，`readonly` 自身的退出码是 0，脚本认为一切正常。中间 `cd` 的失败被彻底吞掉。

正确写法是**声明和赋值分离**：

```console
$ cat sc_demo2.sh
set -e
GOOD="$(cd /nonexistent && pwd)"
readonly GOOD
echo "这行不打印 → set -e 正常生效"

$ ./sc_demo2.sh
sc_demo2.sh: line 4: cd: /nonexistent: No such file or directory
退出码: 1                    ← 正确
```

**这就是 shellcheck 的 SC2155。** 本仓库的脚本现在全部采用分离写法（`01-stats.sh` 的 `SCRIPT_DIR`，`04-backup.sh` 的 `SRC_NAME` / `STAMP` / `SRC_SIZE` / `ARCHIVE_SIZE`）。

**通用规则：任何被 `readonly` / `export` / `local` 修饰的变量，如果赋值来自命令替换，就拆成两行。**

---

## 9. 思考题答案

### 1. `set -e` 的局限性

**如果你写的判断本身就靠命令失败来分支，`-e` 会直接把你踢出去。**

具体表现：命令替换里套了个"允许失败"的命令：

```bash
set -e
count=$(grep -c PATTERN file)   # 零匹配时 grep 返回 1 → 整个脚本退出
```

而你的本意只是想拿到 `0` 这个结果。

**豁免位置**：`if` / `while` 条件、`&&` `||` 左侧、`!` 取反里的失败不会触发。

**解法：** 用 `|| true` 显式声明"这里的失败是预期的"。

### 2. `"$@"` 和 `"$*"` 的区别

`"$@"` 保持参数边界（2 个参数就是 2 个），`"$*"` 用 IFS 拼成 1 个字符串。

**批量删除时的实际后果：**

```bash
# 文件名是 "report 2024.pdf" 和 "notes.txt"
for f in "$@"; do rm -- "$f"; done   # ✅ 删 2 个文件
for f in "$*"; do rm -- "$f"; done   # ❌ "report 2024.pdf notes.txt" 被拆成 3 个词
                                      #    实际尝试删 report / 2024.pdf / notes.txt
```

后者的危险在于：**如果当前目录真有 `report` 这个文件，它会被删掉。**

### 3. 为什么 CI 里的脚本必须加 `set -e`

**考虑这个场景：** 脚本第一步 `cd $DIR` 失败了（目录不存在），但因为没 `set -e`，第二步照常执行 `$DIR/somefile` —— 报错信息指向 `somefile`，而不是真正的元凶 `cd`。

CI 拿到的是"最后一条命令的退出码"。没有 `set -e`，失败被中间步骤吞掉，CI 拿到一个误导性的结果。

**结论：`set -euo pipefail` 是 CI 脚本的最低门槛。** 它保证"任何一步失败，CI 立刻红，并且停在失败的那一步"。

### 4. CI 机器和本地的差异

| 维度 | 本地 WSL | GitHub Actions |
|---|---|---|
| 系统 | Ubuntu 26.04 | `ubuntu-latest`（版本会变） |
| 用户 | `anguish` | `runner` |
| 装的东西 | 你装的那些 | 几乎什么都没有 |
| 文件 | 你的文件系统 | 全新环境，每次重置 |
| 状态 | 持久的 | **每次 PR 都是干净的** |
| 权限 | 你的 umask | 固定 |
| 网络 | 你的网络 | GitHub 机房 |

**"每次都是全新的干净环境"这一条最重要** —— 它意味着本地能跑不代表 CI 能跑，典型差异：

- 依赖没装（本地手动装过，CI 没有）
- 环境变量没设（`~/.bashrc` 里的 export，CI 不会读）
- 你的开发工具/别名/函数在 CI 里不存在
- 依赖了某个"碰巧"存在的文件

**这也是 CI 的价值所在**：它模拟了别人 clone 你仓库后的环境。

### 5. `trap ... EXIT` 解决了什么问题

**没有它：** 脚本在第 3 步（`tar` 打包）失败时退出，目标目录里留下一个 `.tmp-backup-xxx.tar.gz` 残片。

**危害不只是"占空间"：**

- 下次跑脚本时，残留的临时文件可能被 `find` 当成备份
- 名字像 `backup_20260928.tar.gz` 的残片会被误认为有效备份 → **真出事时用它恢复，拿到的是半个包**

**恢复流程里最坏的情况不是"没有备份"，而是"有个备份但它是坏的"。**

---

## 速查

```bash
# 脚本骨架
#!/usr/bin/env bash
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 参数
"$1" "$2"      # 位置参数（带引号）
"$@"           # 所有参数（保持边界）
$#             # 参数个数
${1:-default}  # 有默认值
shift          # 移除第一个参数

# 判断
[[ -f "$f" ]]          # 是文件
[[ -d "$d" ]]          # 是目录
[[ -z "$s" ]]          # 空字符串
[[ "$x" =~ ^[0-9]+$ ]] # 是正整数
[[ "$a" == "$b" ]]     # 相等

# 控制
if/elif/else   for   while read   case
if cmd; then ...; fi          # cmd 失败在 if 里豁免 set -e
cmd || true                  # 显式允许失败

# 清理
trap cleanup EXIT            # 退出时清理（无论怎么退）
trap 'echo int' INT          # Ctrl+C
local x=$?                  # 必须在函数第一行

# 常用
date +%Y%m%d-%H%M%S
mapfile -t arr < <(cmd)      # 读成数组
rm -f -- "$f"                # -- 防选项
tar -czf out.tar.gz -C /path dir/
find . -printf '%T@ %p\n' | sort -rn
```
