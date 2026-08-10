# 创建下一大阶段 `v2`

**何时用**：[`20-push.md`](./20-push.md) 已 PASS（Stage1 收尾完成；默认已有 `release/1.0.0`）。  
**本文件做什么**：从已验收的 **`v1`** 懒创建大阶段 tip **`v2`**。  
**本文件不做什么**：不创建 `v2.1`（等 V2 Phase 1 完成再用 `v2-usage-insights/phases/P01-save.md`）。

---

## 复制给 Cursor 的整段（从下一行开始）

请从已验收的 `v1` 创建大阶段分支 **`v2`**（不要预建小迭代 `v2.1`）。

```bash
git checkout v1 && git pull
git checkout -b v2
```

若远程已有 `v2`：先 `git fetch` 并汇报 tip，**不要**覆盖回退。  

然后：

1. 更新 `BRANCHES.md`（英→中）：`v2` tip 含义 = Stage2 工线已开；Stage1 以 `release/1.0.0` / `v1` 为准冻结。  
2. 经用户确认后：`git push -u origin v2`。  
3. 打开 [`40-checkout-next-branch.md`](./40-checkout-next-branch.md)。  

禁止：force push；预建 `v2.1`…；预建 `v3` / `v4`；把 Stage2 功能直接提交进 `v1`。
