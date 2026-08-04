# V1 完成后 — 切换到 V2 分支提示词

新分支 `002-usage-insights` 已存在后，把下面整段复制给 Cursor。

---

请切换到 V2 工作分支，并确认仓库状态干净、可读文档齐备。

## 步骤

1. `git checkout 002-usage-insights`
2. `git status -sb`：确认分支名与跟踪关系
3. 指出下一步应打开的 playbook：`ApiRelay/specs/playbooks/v2-usage-insights/00-README.md`
4. 提醒：V2 正式开发前建议先跑 `/speckit-specify`（或增量 spec）→ plan → tasks，再按 `phases/` 提示词实现；playbook 里的 Phase 是草案，**以届时生成的 `tasks.md` 为准**。

## 不要做

- 不要合并回 `001-key-vault`
- 不要在未读 V2 README 前大范围改 V1 模块边界

汇报：当前分支、工作区是否干净、建议的下一条提示词路径。
