# linux-journal

> Linux 学习日志：从命令行到系统 internals
>
> 目标读者：会一点基础命令（`cd` / `ls` / `mkdir`），但一到组合就懵的开发者。

这不是一份"看完就完"的教程，而是一条**留痕的学习路径**。每个阶段对应一个 GitHub Issue，
每次提交对应一个 Pull Request，每个 PR 都会被 review。

---

## 学习模型

Unix 的核心哲学是：**每个命令只干一件事，干完把结果吐到屏幕上**。
把它们用 `|` 串起来，就得到了一个强大的系统。

但背命令会忘。所以本仓库采用**工作流驱动**的学习方式：

```
读 issue  →  开分支  →  写代码  →  提交  →  推送  →  开 PR  →  过 CI  →  合并
                ↑                                                ↑
         真正的学习发生在这里                          这里自动帮你验证
```

每个 Linux 知识点都被嵌入一个有目的、有反馈的流程里。学 `git commit` 不是背参数，
是为了"把这个改动交上去"；学 `chmod` 是为了解决"为什么 CI 跑不动脚本"。

---

## 环境

| 项 | 值 |
|---|---|
| 系统 | Ubuntu 26.04 LTS (WSL2) |
| Shell | bash |
| gh | 2.46.0 |
| 项目目录 | `~/workspace/linux-journal`（放在 Linux 盘，别放 `/mnt/c`，慢 185 倍） |

---

## 目录结构

```
linux-journal/
├── data/                    # 练习素材（日志、目录树），只读不改
├── labs/                    # 实验产物，按阶段分目录
│   ├── 01-filesystem/
│   ├── 02-text/
│   ├── 03-permissions/
│   ├── 04-shell/
│   ├── 05-network/
│   ├── 06-docker/
│   └── 07-internals/
├── scripts/                 # 正式交付物（可执行脚本）
├── notes/                   # 实验笔记 → 未来的 internals 文档
└── .github/
    ├── workflows/ci.yml     # 云端 Linux 机器（Phase 4 启用）
    └── ISSUE_TEMPLATE/
```

---

## 路线图

| 阶段 | 主题 | 核心命令 | 状态 |
|---|---|---|---|
| 0 | GitHub 协作闭环热身 | `gh` / `git` 基础 | ⬜ |
| 1 | 文件系统与管道 | `ls` `find` `grep` `sort` `uniq` `wc` `>` `\|` | ⬜ |
| 2 | 文本三剑客 | `grep -E` `sed` `awk` `vim` | ⬜ |
| 3 | 权限与进程 | `chmod` `chown` `ps` `kill` `nohup` `free` `df` `du` | ⬜ |
| 4 | Shell 脚本与 CI | `if` `for` `case` `set -euo pipefail` / GitHub Actions | ⬜ |
| 5 | 网络与远程运维 | `ip` `ss` `curl` `ssh` `rsync` `systemctl` | ⬜ |
| 6 | Docker | `docker` `Dockerfile` `compose` | ⬜ |
| 7 | 系统原理 | `strace` `fork` `cgroup` `namespace` | ⬜ |
| 8 | 真实开源贡献 | 给别人的仓库提 PR | ⬜ |

进度看板用命令行查，不用刷网页：

```bash
gh issue list --label "phase/1"
```

---

## 约定

- **commit message** 遵循 [Conventional Commits](https://www.conventionalcommits.org/)：
  `feat:` `fix:` `docs:` `refactor:` `chore:` `test:`
- **一个 PR 只做一件事**，超过 300 行 diff 就该拆
- **每个 PR 必须自 review**：`gh pr diff` 自己看一遍再合
- **CI 绿了才合**，CI 本质就是一台云端 Linux 机器

---

## 快捷命令

```bash
gh issue list                    # 我的任务清单
gh issue view 1                  # 看详情
git switch -c feat/xxx           # 开分支干活
gh pr create --fill              # 开 PR
gh pr diff                       # 自查改动
gh pr checks                     # 看 CI
gh pr merge --squash             # 合并
```
