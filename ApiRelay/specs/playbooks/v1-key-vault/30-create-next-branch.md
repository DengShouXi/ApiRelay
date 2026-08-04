# V1 完成后 — 创建下一版本分支提示词

V1 已合并进 `main`（或你已确认 main 含 V1）后，把下面整段复制给 Cursor。

---

请按 ROADMAP 约定，为 **V2** 创建功能分支。

## 目标

- 从最新 **`main`** 创建并推送分支：`002-usage-insights`
- 不要在这个分支上开始写业务代码（除非我接着贴 V2 的 Phase 提示词）

## 步骤

1. `git fetch origin`；确认 `main` 已包含 V1（或说明差距）。
2. `git checkout main` && `git pull`（若有远程）。
3. `git checkout -b 002-usage-insights`
4. （可选）在 `ApiRelay/specs/002-usage-insights/` 放一个简短 `README.md`，写明「增量规格待 `/speckit-specify` / plan / tasks」——**不要**改 `001-key-vault` 的已定稿决策编号。
5. `git push -u origin 002-usage-insights`（推送前先问我确认）。

## 不要做

- 不要从旧的 `001-key-vault` 直接分支（避免漏掉 merge 进 main 的修复）
- 不要删除 `001-key-vault` 分支（除非我要求）

完成后提示我打开 `40-checkout-next-branch.md`。
