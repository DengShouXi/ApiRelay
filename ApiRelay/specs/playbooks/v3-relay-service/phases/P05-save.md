# V3 中转服务 · Phase 5 — 检查点保存与上传提示词

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到小阶段分支。**不要**继续写实现代码。

---

请为 **V3 中转服务 · Phase 5（用量与轮换）** 做检查点保存并上传到远程。

## 固定目标（写错分支视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层，可选同步） | `v0.3` |
| **小阶段分支（第 3 层，本次上传目标）** | `v0.3.5` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 对应实现提示词 | `phases/P05-用量与轮换.md`（本对话不实现） |
| 本阶段测试目录 | `ApiRelay/ApiRelayTests/V3/Phase05_Ledger/` |

## A. 更新分支备注（必须英 → 中）

编辑 `BRANCHES.md`，为小阶段分支 **`v0.3.5`** 写入/更新：

1. **English**（2–4 句）：相对上一小阶段多了什么、不含什么、何时 checkout `v0.3.5`。  
2. **简体中文**：同样信息。  
3. 记录 tip commit（push 后的 hash）。

确认命名：`v0` 未上架；`v0.3` 大阶段；`v0.3.N` 小阶段分支。无 `v0.4`。

## B. 提交并推到小阶段分支 `v0.3.5`

1. 汇报：`git status -sb`、`git branch --show-current`、`git log -5 --oneline`。  
2. 若当前不在 `v0.3.5`：从大阶段线创建或检出  
   `git checkout v0.3` && `git pull` && `git checkout -B v0.3.5`  
   （`-B` 把本小阶段分支指到当前大阶段最新提交；**经我确认后再执行**）。  
3. 暂存：本 Phase 实现 + 对应 `ApiRelayTests/V3/Phase05_*/` 测试 + `BRANCHES.md`。  
4. **禁止**加入：`ApiRelay/build/`、`ApiRelay/DebugScratch/`、`__pycache__/`、`spec-kit-0.15.2/`、密钥、`.env`。  
5. 展示 `git diff --cached --stat`，**等我同意后再 commit**。  
6. 建议 message：

```text
feat(v0.3.5): Phase 5 用量与轮换 checkpoint
```

7. 上传小阶段分支：

```bash
git push -u origin v0.3.5
```

8. （推荐）同步大阶段分支尖端：`git checkout v0.3` && `git merge v0.3.5` && `git push origin v0.3`，再回到 `v0.3.5`。

## C. 完成汇报

- 小阶段分支 `v0.3.5` @ `<hash>`（远程已有）  
- `BRANCHES.md` 是否已含英+中  
- 测试是否只在 `ApiRelayTests/V3/Phase05_*/`  
- 下一步：下一 Phase 的**实现**提示词；新小阶段将上传到 `v0.3.6`  

## 禁止

- 把第三层建成 Git tag（按你的命名：第三层是**分支**）  
- 预建未开始的 `v0.2` / `v0.3` / `v0.4`  
- force push；把 `DebugScratch` 或 `build` 推上去  
