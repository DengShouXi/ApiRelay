# V3 完成后 — 回到稳定分支提示词

---

请切换到稳定发布线：

```text
git checkout main
git pull
git status -sb
```

确认工作区干净，并报告当前 tag 列表中与 ApiRelay 相关的最新 tag。  
日常开发若无新 ROADMAP 阶段，应基于 `main` 开短生命周期分支，而不是继续堆在 `003-relay-service`。
