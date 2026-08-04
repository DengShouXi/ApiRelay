# V1 完成后 — 创建大阶段分支 `v0.2` 提示词

把下面整段复制给 Cursor。

---

请**懒创建**产品大阶段 2 的工作分支（现在才允许创建）。

## 固定目标

| 项 | 值 |
|----|-----|
| 来源 | 已验收的 `v0.1`（建议已有 tag `v0.1.8`） |
| 新建分支 | `v0.2` |
| 首个小检查点 tag | 尚未打；等 V2 Phase 1 完成后再打 `v0.2.1` |
| 台账 | 更新 `BRANCHES.md`：为分支 `v0.2` 写 English + 简体中文 |

## 步骤

1. 确认 V1 收尾核对已通过。  
2. `git checkout v0.1` && `git pull` && `git checkout -b v0.2`  
3. 更新 `BRANCHES.md`（英→中说明 `v0.2` 起点）。  
4. 展示 diff，经我确认后 commit + `git push -u origin v0.2`。  
5. 打开 [`40-checkout-next-branch.md`](./40-checkout-next-branch.md)。

## 禁止

创建 `v0.3`/`v0.4`；删除 `v0.1` 或历史 tag；force push。
