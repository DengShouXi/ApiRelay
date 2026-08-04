# V1 — 密钥保险库 Playbook

**工作分支（第 2 层）**：`v0.1`  
**小阶段检查点（第 3 层）**：tag `v0.1.1` … `v0.1.8`  
详见 [BRANCHES.md](../BRANCHES.md)。

## 一句话

密钥保管与分发；**完全不联网调上游**。

## Phase ↔ tag

| Phase | 主题 | 实现提示词 | 完成后 tag |
|-------|------|------------|------------|
| 1 | 工程配置 | [`phases/P01-工程配置.md`](./phases/P01-工程配置.md) | `v0.1.1` |
| 2 | Data 层 | [`phases/P02-Data层.md`](./phases/P02-Data层.md) | `v0.1.2` |
| 3 | 保管与取出 | [`phases/P03-保管与取出.md`](./phases/P03-保管与取出.md) | `v0.1.3` |
| 4 | 指派与双视角 | [`phases/P04-指派与双视角.md`](./phases/P04-指派与双视角.md) | `v0.1.4` |
| 5 | 付费解锁 | [`phases/P05-付费解锁.md`](./phases/P05-付费解锁.md) | `v0.1.5` |
| 6 | 设置与备份 | [`phases/P06-设置与备份.md`](./phases/P06-设置与备份.md) | `v0.1.6` |
| 7 | Catalyst | [`phases/P07-Catalyst.md`](./phases/P07-Catalyst.md) | `v0.1.7` |
| 8 | 安全审查 | [`phases/P08-安全审查.md`](./phases/P08-安全审查.md) | `v0.1.8` |

每 Phase：`05-annotate-branch` → `15-phase-push`（**tag**，人留在 `v0.1`）。
