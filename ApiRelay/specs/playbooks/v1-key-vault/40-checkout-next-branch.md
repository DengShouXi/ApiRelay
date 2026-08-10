# 切换到大阶段 `v2`

**何时用**：[`30-create-next-branch.md`](./30-create-next-branch.md) 已把 **`v2`** 推上远程。

```bash
git checkout v2
git pull
```

然后打开 Stage2 playbook：

→ [`../v2-usage-insights/00-README.md`](../v2-usage-insights/00-README.md)

之后每个小迭代：实现 `P0N-*.md` → 保存 `P0N-save.md` 推到 **`v2.N`**。  
Stage1 文档与 `release/1.0.0` 热修若需要，回到 `v1` / 新 `v1.N` 热修分支，**不要**在 `v2` 上改 Stage1 上架材料职责边界。
