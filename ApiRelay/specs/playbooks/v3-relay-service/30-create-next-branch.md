# V3 完成后 — 分支策略提示词

---

V3 是 ROADMAP 定义的最后一阶段，**默认不再创建 V4 分支**。

请执行（经我确认）：

1. 确保 `003-relay-service` 已合并进 `main`（或说明未合并原因）
2. 在 `main` 上打发布 tag（如 `v3.0.0-relay`）
3. 若有热修需求：从 tag / main 开 `hotfix/*`，不要发明「V4」除非新产品范围已写入 ROADMAP

若未来确有 V4：先修订 `specs/ROADMAP.md`（需我确认决策变更），再新建 playbook。
