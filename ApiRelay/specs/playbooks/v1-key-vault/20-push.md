# V1 — 上传（push）提示词

V1 验收通过后，把下面整段复制给 Cursor。**仅在你明确要求提交/推送时执行 git 写操作。**

---

请帮我把 **V1（分支 `001-key-vault`）** 上传到远程。

## 步骤（按序，遇到需确认处先问我）

1. `git status` / `git diff` / `git log -5`：说明将要包含的变更范围；**不要**提交密钥、`.env`、证书、含明文的调试文件。
2. 若有未提交改动：先按我的确认创建 commit（conventional 风格，说明 V1 完成点）；**未经我同意不要 commit。**
3. 确认当前分支是 `001-key-vault`，且已跟踪远程（必要时 `git push -u origin HEAD`）。
4. 推送成功后报告：远程 URL、分支名、最新 commit hash。
5. **可选（需我明确说「合并并打 tag」）**：开 PR 合并进 `main`，合并后打 tag（如 `v1.0.0-key-vault`）。V2 分支必须从**已含 V1 的 main**切出。

## 不要做

- 不要 force push
- 不要改 git config
- 不要开始 V2 实现

完成后提示我打开 `30-create-next-branch.md`（若 main 已含 V1）或先完成合并再打开。
