# V1 — 每个小 Phase 上传提示词

某个 Phase 的 Checkpoint 通过后使用。**先做** [`05-annotate-branch.md`](./05-annotate-branch.md)，再贴本段。

---

请把 **V1 当前小阶段**做成远程里程碑分支并上传。

## 命名

- 大阶段固定第二位 = `1`  
- 第三位 = 刚完成的 Phase 编号 → Phase 1 完成推 `v0.1.1`，Phase 2 → `v0.1.2`，…，Phase 8 → `v0.1.8`  
- 若该分支名已存在且指向旧提交：在其上继续 commit 后 `git push`；**不要**改写已推送历史。

## 步骤（需我确认才 commit / push）

1. `git status` / `git diff` / `git log -5`：说明范围；禁止提交密钥、`.env`、`build/`、明文调试文件。  
2. 确认 `BRANCHES.md` 已含本分支英+中备注。  
3. 经我同意后 commit（建议 subject 含 Phase 编号，body 可一行中文说明）。  
4. 若当前不在目标名：`git branch -m v0.1.N` 或从当前 HEAD `git branch v0.1.N` 再检出。  
5. `git push -u origin v0.1.N`  
6. 报告：远程 URL、分支名、commit hash。可选：该分支是否设为默认分支（仅当我要求）。

## 不要做

- 不要 force push  
- 不要开始下一个 Phase 的实现（除非我接着贴下一份 `phases/P0N`）  
- 不要删 `v0.0.1` / `v0.0.2`  

完成后告诉我下一份应打开的提示词（下一 Phase，或全部完成后的 `10-verify.md`）。
