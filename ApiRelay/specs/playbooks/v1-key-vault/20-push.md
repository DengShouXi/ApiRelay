# V1 — 大阶段收尾核对（T062 之后）

**何时用**：[`12-release-T062.md`](./12-release-T062.md) 已完成（或你已书面确认等价：`main` + `release/1.0.0` 已就位）。  
**本文件做什么**：确认 Stage1 远程与台账可冻结，然后才能开大阶段 **`v2`**。  
**本文件不做什么**：不创建 `v2.1`、不开始用量/探活实现。

```text
12-release-T062 完成
  → 【本文件】20-push
  → 30-create-next-branch（建 v2 tip）
  → 40-checkout-next-branch
```

---

## 复制给 Cursor 的整段（从下一行开始）

请核对大阶段 **`v1` 收尾状态**。不要 force push，不要预建 `v4`，不要创建 `v2.1`。

### 核对表

| # | 检查 | 期望 |
|---|------|------|
| 1 | 小迭代分支 | `v1.1`…`v1.13`（及已有热修）均在 `origin` |
| 2 | tip `v1` | 指向 Stage1 最终 tip（通常 = `v1.13` 或其后热修） |
| 3 | `main` | 已包含 Stage1 上架内容（若 T062 已合并） |
| 4 | tag | 远程存在 **`release/1.0.0`**（仅上架 tag） |
| 5 | `BRANCHES.md` | 每条小迭代有英+中；`v1.13` / T062 / `release/1.0.0` 状态一致 |
| 6 | `tasks.md` | T062 已勾（若发布已完成）；无「材料未齐却已 tag」矛盾 |
| 7 | 测试目录 | 实现测试仍在 `ApiRelayTests/V1/Phase*/`，未混进 V2 目录冒充完成 |
| 8 | 商店边界 | 台账/README 未把探活、用量看板写成 Stage1 已交付 |

### 汇报

- 收尾判定：PASS / FAIL  
- PASS → 打开 [`30-create-next-branch.md`](./30-create-next-branch.md)  
- FAIL → 列出缺口；**不要**创建 `v2`

---

## 本文件完成后（不要复制进 Cursor）

通过后打开 [`30-create-next-branch.md`](./30-create-next-branch.md)。  
若尚未真正提交审核、只想先开 `v2` 文档线：须你**另句确认**「允许在 T062 未完成时创建 `v2` tip」——默认不允许。
