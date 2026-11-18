# Git 版本回档手册

> 适用仓库：`git@github.com:xsg1203/fpga-git-starter.git`
> 当前版本线：`v0.1-spec`（规格书）→ `v0.2-m2`（采集直显）→ main（SSH 推送配置）
> 环境：Git 2.55 / Git Bash（已确认支持 `switch`、`restore`）

---

## 0. 第零步：永远先让工作区变干净

回档出问题，九成是**带着未提交的改动去切换版本**。切换时 Git 有两种表现：
能带过去的就默默带过去（改动跟着进旧版本，最容易搞混），带不过去的直接报错中止。

所以每次回档前先看：

```bash
git status
```

- 输出 `nothing to commit, working tree clean` → 可以直接往下走
- 有 `modified:` 文件 → 先二选一处理掉：

```bash
# 选择一：这些改动还有价值，先提交（推荐）
git add -A && git commit -m "wip: 上板前暂存"

# 选择二：这些改动是垃圾，确认不要了再丢弃（不可恢复，慎重）
git checkout -- .            # 丢弃所有未暂存改动
git checkout -- docs/03_上板调试记录.md   # 只丢弃某一个文件
```

> 不确定要不要丢的，用 `git stash push -m "临时存一下"`，它会存起来且不产生提交，
> 之后 `git stash pop` 可原样取回。`git stash list` 查看存了什么。

---

## 1. 先分清你要哪一种"回退"

| 你的真实意图 | 正确做法 | 是否会毁掉已有提交 |
|---|---|---|
| 只想**看看**旧版本代码长什么样 | 另开分支 / worktree 查看 | 不会 |
| 想在旧版本基础上**继续开发**（保留现在的 main） | 从 tag 拉新分支开发 | 不会 |
| 确认新版本有问题，**彻底退回**旧版本，之后提交都不要了 | `git reset --hard` | 会（本分支历史被改写） |
| 已经推到 GitHub 了，想撤销某次提交但**保留历史** | `git revert` | 不会 |
| 只有某一个文件改坏了，想恢复成旧版本 | `git restore --source=` | 不会 |
| 误操作导致提交"丢了" | `git reflog` 找回 | 不会 |

---

## 2. 场景 A：只是想看旧版本（最常用）

先建一个临时分支，看完删掉，全程不碰 `main`：

```bash
# 1. 从 M2 里程碑建临时分支并切过去
git switch -c look-m2 v0.2-m2

# 2. 随便看代码、对比、甚至跑综合，都不会影响 main
git log --oneline -3
git diff v0.2-m2..v0.1-spec        # 看两个里程碑之间改了什么

# 3. 看完切回主线
git switch main

# 4. 删掉临时分支
git branch -D look-m2
```

> **为什么不直接 `git checkout v0.2-m2`**：那会进入 detached HEAD 状态，
> 此时产生的提交不属于任何分支，一切回 main 就容易"凭空消失"。
> 临时分支没有这个风险，代价只是多敲两行命令。

如果你连分支都不想建，用 worktree 让旧版本出现在另一个目录（推荐同时对比改动时用）：

```bash
git worktree add ../look-m2 v0.2-m2   # 在上级目录生成 look-m2 文件夹
# 看完后
git worktree remove ../look-m2
```

---

## 3. 场景 B：在旧版本基础上继续开发

比如 M3 做砸了，想从 M2 重新起一条路，但**不想删掉现在的 main**：

```bash
git switch -c m3-retry v0.2-m2   # 从 M2 拉分支
# 在这里重新做 M3
```

确认新分支可用后，再决定要不要让它取代 main：

```bash
git switch main
git reset --hard m3-retry        # 只有确认后才执行
```

这样旧路线在 `m3-retry` 之外的提交依然可通过 reflog 找回，比直接 reset 安全得多。

---

## 4. 场景 C：彻底退回旧版本（`reset --hard`）

**这一步会丢弃之后的提交**，执行前务必确认。适用于"当前 main 已经跑偏，就当没做过"。

```bash
# 1. 保险：先给当前位置打个记号，万一后悔还能回来
git tag before-reset

# 2. 硬回退到 M2
git reset --hard v0.2-m2

# 3. 确认
git log --oneline -3
git status
```

此时本地已在 `v0.2-m2`，但**远端还是旧的**，必须再处理远端：

```bash
# 强制覆盖远端（历史被改写）
git push --force-with-lease origin main

# 确认远端已跟上
git ls-remote origin
```

> 用 `--force-with-lease` 而不是 `--force`：前者在远端存在你没拉取过的提交时会**拒绝执行**，
> 避免覆盖掉你在 GitHub 网页上直接改的内容。个人课设仓库用强推可以接受，
> 但仍建议守住这条。如果 `--force-with-lease` 被拒，先 `git fetch` 看清远端到底多了什么。

回退成功后删掉记号（否则以后每次看 tag 列表都会混淆）：

```bash
git tag -d before-reset
```

### 4.1 为什么不能"用 revert 范围退回"（本仓库实测结论）

网上常见写法是 `git revert --no-commit v0.2-m2..HEAD`，它在本仓库**跑不通**，我实测过：

```
error: commit 0fd35206... is a merge but no -m option was given.
fatal: revert failed
```

原因：`v0.2-m2..HEAD` 范围内有 `0fd3520 chore: 合并远端 Initial commit` 这个**合并提交**。
加上 `-m 1` 指定主线后，仍然会撞上 `modify/delete` 冲突（README 在远端 Initial commit 里
被删除、在当前 HEAD 里被修改），需要人工解冲突，得不偿失。

**结论：本仓库要整体退回旧版本，就用 `reset --hard` + `push --force-with-lease`。**
这个仓库是你一个人的，历史被改写没有协作风险，比解一堆 revert 冲突干净得多。

如果确实需要保留"曾经做过新版本"这条历史痕迹，用**场景 B**：从 tag 拉一条新分支
`git switch -c v2-from-m2 v0.2-m2` 继续做，让旧路线留在原 main 上，最后再决定合并或替换。
这比 revert 更符合直觉，也不会产生冲突。

---

## 5. 场景 D：只回退单个文件

最安全的一类回退，不影响任何提交。

```bash
# 把 ct_top.v 恢复成 M2 时的样子
git restore --source=v0.2-m2 -- rtl/ct_top.v

# 恢复整个目录
git restore --source=v0.1-spec -- rtl/
```

注意 `git restore` 只改工作区。恢复后要提交才会进入版本库：

```bash
git add rtl/ct_top.v && git commit -m "revert(rtl): ct_top 回退到 M2 版本"
```

旧写法（Git 2.23 以前常见，现在仍可用）：`git checkout v0.2-m2 -- rtl/ct_top.v`

---

## 6. 场景 E：提交"丢了"怎么找回

`reset --hard` 之后、或者误删分支之后，提交其实还在 Git 对象库里，靠 reflog 找回：

```bash
git reflog                  # 列出最近所有 HEAD 移动记录
# 找到形如 3b928f0 HEAD@{5}: reset: moving to v0.2-m2 的那行

git switch -c rescue 3b928f0   # 用它建分支，内容立刻回来
```

reflog 只记录本地操作，默认保留 90 天。**这是最后的救生圈，所以 `reset --hard` 之前不必过于紧张，但一定要在 90 天内发现。**

---

## 7. 本项目特有的注意事项（重要）

### 7.1 回档后必须重建 Vivado 工程

`.gitignore` 已排除 `*.xpr`、`.runs/`、`.cache/`、`*.bit` 等所有生成物——仓库里只有**源码、约束、脚本、文档**。

因此回档后**不存在现成的工程文件**，必须重新生成：

```bash
# 在 Vivado Tcl Console 里
source scripts/create_project.tcl
```

跑完综合实现后要重新生成比特流。这是刻意的设计：`.xpr` 是 XML 但夹带大量绝对路径，`.bit` 是大二进制，两者入库都会让 diff 和回档失去意义。

### 7.2 回档不改变硬件状态

回档只恢复**代码**。板子上跑的还是上一次下载的比特流。要验证旧版本，必须重新综合并下载。

### 7.3 里程碑要打 tag

一个里程碑验证通过（比如 M2 上板出图正常）就立刻打 tag，否则以后只能在提交信息里翻：

```bash
git tag -a v0.3-m3 -m "M3 块统计 + 五色投票"
git push origin --tags
```

tag 名约定：`v<主版本>.<里程碑>-m<n>`，与 `docs/01_需求规格书.md` §8 的里程碑表对应。

### 7.4 推送仍用脚本

```bash
./scripts/push.sh     # 走 SSH
```

---

## 8. 不要做的事

| 危险操作 | 后果 | 替代做法 |
|---|---|---|
| `git reset --hard` 前不看 `git status` | 未提交改动永久丢失 | 先 commit 或 stash |
| 直接 `git checkout v0.2-m2` 然后在上面改代码 | 提交不在任何分支，切走后"消失" | `git switch -c 分支名 v0.2-m2` |
| 对已推送的历史用 `reset` + `--force` | 远端历史被改写，其他人拉取报错 | `git revert` 或 `--force-with-lease` |
| 用 `git clean -fdx` 清工作区 | 会删掉未入库的工程目录和比特流 | 只删已知冗余文件 |
| 把 `.xpr` / `.bit` / `.runs` 提交进去 | 仓库膨胀、diff 全是噪声、回档失效 | 已在 `.gitignore` 拦截，不要用 `-f` 强加 |

---

## 9. 一页速查

```bash
# 看状态（每次操作前都要做）
git status
git log --oneline --decorate --graph -10
git tag -l -n1

# 看旧版本
git switch -c look-m2 v0.2-m2        # 临时分支查看
git switch main && git branch -D look-m2

# 从旧版本开发
git switch -c m3-retry v0.2-m2

# 彻底退回
git tag before-reset
git reset --hard v0.2-m2
git push --force-with-lease origin main
git tag -d before-reset

# 撤销某次提交（保留历史）
git revert <commit>

# 单文件回退
git restore --source=v0.2-m2 -- <文件>

# 找回丢失提交
git reflog
git switch -c rescue <sha>

# 打里程碑标签
git tag -a v0.3-m3 -m "M3 块统计 + 五色投票"
./scripts/push.sh
```
