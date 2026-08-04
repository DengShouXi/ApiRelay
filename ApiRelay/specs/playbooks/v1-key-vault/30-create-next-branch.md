# 创建下一大阶段 `v0.2`

把下面复制给 Cursor。

---

从已验收的 `v0.1`（建议已有 `v0.1.8`）懒创建大阶段分支：

```bash
git checkout v0.1 && git pull
git checkout -b v0.2
```

更新 `BRANCHES.md`（英→中），经确认后 `git push -u origin v0.2`。  
**不要**现在创建 `v0.2.1`（等 V2 Phase 1 完成再用 `P01-save.md`）。然后打开 `40-checkout-next-branch.md`。
