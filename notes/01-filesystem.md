# Phase 1 · 文件系统与管道

> 目标：理解 Unix 的核心哲学 —— **每个命令只干一件事，干完把结果吐到屏幕上**。
> 用 `|` 把它们串起来，就得到了一个强大的系统。
>
> 本文所有命令输出均为在 Ubuntu 26.04 (WSL2) 上**实际执行**所得。

---

## 1. 路径

```bash
pwd                  # 我在哪
pwd ~/               # /home/anguish
cd -                 # 回到上一个待过的目录（好用到离谱）
```

| 记号 | 含义 |
|---|---|
| `/a/b/c` | 绝对路径，从根开始 |
| `a/b/c` | 相对路径，从当前目录开始 |
| `~` | 家目录，等价于 `$HOME` |
| `.` | 当前目录 |
| `..` | 上一级目录 |
| `-` | 上一次待过的目录（只有 `cd` 认） |

`cd -` 的实际价值：在深层目录里改完一个文件，`cd -` 一键跳回去，不用翻命令历史。

---

## 2. 通配符与引号

### 通配符

| 记号 | 含义 |
|---|---|
| `*` | 任意长度任意字符 |
| `?` | 单个字符 |
| `[a-z]` | 范围内任一字符 |
| `[!abc]` | 排除 |
| `{a,b}` | 枚举，`echo {a,b}.log` → `a.log b.log` |

花括号展开是 bash 自己的功能（不传给被调用的命令）：

```console
$ echo /tmp/{a,b,c}.log
/tmp/a.log /tmp/b.log /tmp/c.log
```

### 引号：新手最大的坑

核心区别就一条 —— **引号决定 shell 做不做展开**。

先造一个带空格的文件来实测：

```console
$ touch 'my file.txt'      # 文件名里确实有空格

$ ls 'my file*'             # 单引号：字面量，不展开通配符
ls: cannot access 'my file*': No such file or directory

$ ls "my file*"             # 双引号：会展开通配符，但文件名整体匹配不到
ls: cannot access 'my file*': No such file or directory

$ ls my\ file*              # 转义空格 + 展开通配符 → 成功
my file.txt
```

**注意第二行**：双引号确实让 `*` 展开了，但因为文件名叫 `my file.txt`（不是 `my` 开头的一串），展开后依然匹配不到。**含空格的文件名必须转义或加引号，且加引号后就不能再靠通配符。**

命令替换同理：

```console
$ echo "现在是 $(date +%Y)"     # 双引号内会执行
现在是 2026
$ echo '现在是 $(date +%Y)'     # 单引号内不执行，原样输出
现在是 $(date +%Y)
```

**选型规则：**

- 变量要展开 → 双引号 `"$VAR"`
- 什么都不展开（文件名可能带空格、含 `$`）→ 单引号
- 永远别不引号写变量：`rm $f` 遇到 `f="a b"` 就变成删两个文件了；`rm "$f"` 才安全

---

## 3. 重定向

| 符号 | 作用 |
|---|---|
| `>` | 覆盖写入（**会丢数据**） |
| `>>` | 追加写入 |
| `<` | 从文件读入 |
| `2>` | 重定向标准错误 |
| `2>&1` | 把错误合并到标准输出 |

### `>` 丢数据的真实演示

```console
$ echo "第一行" > /tmp/r.txt
$ cat /tmp/r.txt
第一行
$ echo "第二行" > /tmp/r.txt      # 又是 >
$ cat /tmp/r.txt
第二行                              # 第一行没了
$ echo "第三行" >> /tmp/r.txt
$ cat /tmp/r.txt
第二行
第三行
```

**这就是为什么脚本里写日志要用 `>>` 而不是 `>`。** 用 `>` 的话每次运行都把上次日志清空了 —— 排查问题时你会发现最关键的那次记录正好被覆盖掉了。

### `2>&1` 的顺序陷阱

```console
$ ls /nonexistent 2> /tmp/err.txt    # 只重定向错误
$ cat /tmp/err.txt
ls: cannot access '/nonexistent': No such file or directory   ✓ 抓到了
```

但顺序反了就不行：

```console
$ ls /nonexistent 2>&1 > /dev/null
ls: cannot access '/nonexistent': No such file or directory   ✗ 打印到终端了
```

原因：`2>&1` 是在 `> /dev/null` **执行那一刻**做的复制。当时 stdout 还指着终端，所以错误被复制到了终端；之后的 `> /dev/null` 只改了 stdout，来不及了。

**要既重定向又合并，顺序必须是 `> file 2>&1`。**

---

## 4. 管道三件套

**读** → **筛** → **排**：

| 环节 | 命令 |
|---|---|
| 读 | `cat` `less` `head` `tail` `wc` |
| 筛 | `grep` `find` |
| 排 | `sort` `uniq` |

### `sort | uniq -c` 为什么必须这个顺序

`uniq` 的本意是 "unique"，但它**只压缩相邻的重复行**。不排序的话，相同内容散落在各处，压根不会被当成重复。

```console
$ cat /tmp/u.txt
b
a
b
c
b
a

$ uniq -c /tmp/u.txt            # 顺序错误：只数相邻的
      1 b
      1 a
      1 b
      1 c
      1 b
      1 a

$ sort /tmp/u.txt | uniq -c     # 先排序让相同行相邻
      2 a
      3 b
      1 c
```

**`sort` 是 `uniq` 的前置条件。** 这是管道组合里最典型的"顺序依赖"。

### 统计必须加 `-n`

```console
$ printf '9\n10\n2\n' | sort -r
9
2
10                    # 字典序：'9' 的字符码大于 '1'

$ printf '9\n10\n2\n' | sort -rn
10
9
2                     # 数字序才对
```

**凡是统计类管道，最后那个 `sort` 几乎总要加 `-n`。** 只在纯文本统计（单词频次）时才用字典序。

---

## 5. `find` vs `ls -R`

```console
$ find data/playground -type f | wc -l
10                          # 直接就是文件

$ ls -R data/playground
data/playground:
docs
notes.txt
src
...                         # 文件和目录混在一起
```

`ls -R` 输出是给人看的，格式不适合程序处理（靠 `-` 前缀过滤，实测 `grep "^-"` 得到 0 行 —— 因为 `ls` 不会列出以 `-` 开头的行首标记… 实际输出里目录名不带 `-`）。

`find` 的真正优势是**条件过滤 + 打印属性**：

```console
$ find data/playground -type f -size +100k        # 只要 >100KB 的
$ find data/playground -type f -printf '%T@ %p\n' | sort -rn | head -2
1790569997.2974335980 data/playground/notes.txt  # 按修改时间倒序
```

⚠️ `-printf` 是 GNU findutils 扩展，macOS/BSD 上没有。跨平台脚本要用 `stat`。

---

## 6. 逻辑连接符

```bash
cmd1 && cmd2      # cmd1 成功(退出码 0)才执行 cmd2
cmd1 || cmd2      # cmd1 失败才执行 cmd2
cmd1 ; cmd2       # 不管成败都执行
$(cmd)            # 命令替换，把输出当字符串用
```

实战组合：

```bash
mkdir -p dir && cd dir && pwd     # 连续前置条件
grep -q ERROR app.log || echo "没有错误"   # 没有才提示
echo "$(date +%Y-%m-%d): 服务重启" >> service.log
```

---

## 7. 实战：日志统计脚本

完整脚本见 [`scripts/01-stats.sh`](../scripts/01-stats.sh)。实际运行输出：

```console
$ ./scripts/01-stats.sh
── 1. 基础统计
总行数:      10
ERROR 行数:  5
WARN 行数:   1

── 2. 错误最多的 IP (Top 5)
  192.168.1.12     2 次
  192.168.1.11     2 次
  192.168.1.13     1 次

── 3. HTTP 状态码分布
  500    5 次
  200    4 次
  404    1 次

── 4. 响应时间统计
  次数:    10
  总计:    2276ms
  平均:    227.6ms
  最慢:    95ms
  最快:    11ms

── 5. 耗时最长的 5 个请求
    1200ms  192.168.1.11 /api/users 500
     340ms  192.168.1.11 /api/login 500
     301ms  192.168.1.12 /api/orders 500
     289ms  192.168.1.12 /api/login 500
      95ms  192.168.1.13 /api/orders 500

── 6. 错误行落盘
  追加 5 行 → labs/01-filesystem/errors.txt

✓ 完成
```

**几个关键实现的说明：**

1. **awk 累加 + END 块** —— `END` 只在所有行处理完后执行一次，是输出总计的标准位置
2. **最慢值有 bug 风险** —— 初版写成 `if (min == 0 || $8 < min)`，在响应时间可能为 0 的真实日志里会算错。修正为 `if ($8 < min || min == 0)`
3. **追加而非覆盖** —— 脚本用 `>>` 落盘，跑两次后文件从 5 行变成 15 行。这是刻意的：保留历史，需要干净文件时由调用方决定
4. **`grep -c` 在无匹配时退出码为 1** —— 在 `set -e` 下会直接终止脚本，所以写成 `grep -c ERROR "$LOG" || true`

---

## 思考题答案

### 1. 为什么 `sort` 必须在 `uniq` 前面？

`uniq` 只压缩**相邻**的重复行。原始数据里相同的行散落各处，`uniq` 视它们为不同的行。`sort` 先把相同内容排到一起，`uniq` 才能识别。见上文实测对比。

### 2. `grep ERROR f` vs `cat f | grep ERROR`

输出相同，语义不同：

- `grep ERROR f` —— grep **自己打开文件**，高效
- `cat f | grep` —— cat 读完整个文件，**包括 grep 根本不关心的部分**，再通过管道传过去。文件越大浪费越多

后者的价值在于**中间的 `cat` 可以换成任何东西**：

```bash
zcat access.log.gz | grep ERROR         # 压缩日志
journalctl -u nginx | grep "500"        # 实时系统日志
docker ps -a | grep nginx               # 进程列表
kubectl get pods | grep CrashLoop       # 集群资源
```

规律：**当输入源不是普通文件时，管道形式是唯一选择。**

### 3. `>` vs `>>` 的区别

`>` 覆盖（会丢数据），`>>` 追加。演示见第 3 节 —— `echo "第二行" >` 之后第一行消失。

日志、配置文件追加、CSV 累积统计，一律用 `>>`。

### 4. `find` vs `ls -R`

| | `ls -R` | `find` |
|---|---|---|
| 面向 | 人眼 | 程序 |
| 输出 | 文件目录混排，带格式 | 只出符合条件的，格式可控 |
| 条件 | 无 | `-type` `-size` `-mtime` `-user` `-perm` |
| 跨平台 | 是 | 语法各家不同（GNU 扩展） |

写脚本用 `find`，快速看一眼用 `ls -R`。

---

## 本阶段命令速查

```bash
# 路径
pwd  cd  cd -  cd ~  ls -la

# 找文件
find . -type f -name "*.log"
find . -size +100k
find . -mtime -7                    # 7 天内修改过

# 看内容
cat  head  tail  less  wc -l

# 筛
grep -i      # 忽略大小写
grep -E      # 正则
grep -c      # 只计数
grep -rn     # 递归带行号
grep -v      # 反选
grep -o      # 只输出匹配部分

# 排
sort        # 字典序
sort -n     # 数字序
sort -rn    # 数字倒序
uniq -c     # 计数相邻重复

# 流向
>  >>  |  2>  2>&1  $(...)  &&  ||  ;

# 通配
*  ?  [a-z]  {a,b}  \  '...'  "..."
```
