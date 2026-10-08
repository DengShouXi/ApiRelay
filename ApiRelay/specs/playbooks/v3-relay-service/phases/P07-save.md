# V3 中转服务 · 小迭代 Phase 7 — 保存并上传提示词

> **现行闸门**：本页的分支名和命令是阶段示例；完成内容不自动授权创建分支、commit、push 或移动大阶段 tip。实际操作先按 `ZL00/03`、`ZL01/09` 核对用户本次范围。备注如需入库仍用 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本提示只处理保存目标，不继续写实现代码；是否本地 commit、远端 push 或只报告待授权，按用户本次明确指令决定。

命名记法：`plan.N`（规划）或 `v{阶段}.{小迭代}`（产品）—— **开发里程碑用分支**；商店上架才打 `release/N.0.0` tag。

---

请为 **V3 中转服务 · Phase 7（隐私与收尾）** 保存本小迭代并上传。

执行下列任何 Git 命令前，分别核对创建分支、本地 commit、目标小迭代分支 push 和大阶段 tip 移动是否已获授权；未获授权的步骤只列为待办，不执行。保存完成不等于上传或发布授权。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v3` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v3.7` |
| 下一小迭代（本步不要创建） | `v3.8` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P07-隐私与收尾.md` |
| 本迭代测试目录 | `ApiRelay/ApiRelayTests/V3/Phase07_Privacy/` |

## A. 本次范围包含迭代备注时更新（英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v3.7`** 写入/更新：

1. **English**（2–4 句）：相对上一小迭代多了什么、不含什么、何时 `git checkout v3.7`。  
2. **简体中文**：同样信息。  
3. 只记实际已产生的 commit SHA；远端结果须在 push 后核对，不预填。

## B. 提交并推到小迭代分支 `v3.7`

1. 汇报：`git status -sb`、`git branch --show-current`、`git log -5 --oneline`。  
2. 核对当前工作树、目标分支是否已存在及其基线 SHA。仅在本次授权包含建分支时，从已确认的 `v3` 基线创建 `v3.7`；已存在则安全切换，不使用 `checkout -B` 重置分支，不在脏树里盲目 `pull`。

3. 只暂存本次批准范围内的 Phase 实现与测试；`BRANCHES.md` 只有在本次范围含迭代备注时才加入，不因模板默认扩大路径。
4. **禁止**加入：`ApiRelay/build/`、`ApiRelay/DebugScratch/`、`__pycache__/`、`spec-kit-0.15.2/`、密钥、`.env`。  
5. 展示 `git diff --cached --stat` 并核对精确路径；本次授权已包含本地提交才 commit，否则停在待授权。
6. 建议 message：`feat(v3.7): Phase 7 隐私与收尾 iteration`  
7. 上传本小迭代：

```bash
git push -u origin v3.7
```

8. （仅在另获明确授权、当前工作树可安全切换且祖先关系／目标 SHA 已核对时）同步大阶段线；只允许 fast-forward：

```bash
git checkout v3
git merge --ff-only v3.7
git push origin v3
git checkout v3.7
```

## C. 完成汇报

- 仅在实际推送并核对远端 SHA 后，报告小迭代 `v3.7` @ `<hash>` 已在远程；否则如实报告未上传。
- `BRANCHES.md` 已有英 + 中备注  
- 测试仅在对应 `Phase07_Privacy/`  
- 下一步：打开下一 Phase **实现**提示词；保存时再开下一小迭代 `v3.8`  

## 禁止

- 用 Git tag 充当小迭代名（禁止；上架才打 `release/N.0.0`；迭代一律用分支）  
- 预建未开始的大阶段 / 小迭代（如 `v3.8` 要等下一 Phase 完成再开）  
- 预建未开始的下一产品大阶段（如尚无 Stage2 时预建 `v2`）；force push；上传 `build` / `DebugScratch`  
