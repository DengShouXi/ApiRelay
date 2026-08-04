# V1 — 密钥保险库 Playbook

**工作分支（第 2 层）**：`v0.1`  
**小阶段检查点（第 3 层）**：tag `v0.1.1` … `v0.1.8`  
台账：[BRANCHES.md](../BRANCHES.md)

## 一句话

密钥保管与分发；**完全不联网调上游**。

## Phase 对照表（实现 / 保存 分开）

| Phase | 主题 | 实现提示词（复制实现） | 保存/上传提示词（复制上传） | tag |
|-------|------|------------------------|-----------------------------|-----|
| 1 | 工程配置 | [`phases/P01-工程配置.md`](./phases/P01-工程配置.md) | [`phases/P01-save.md`](./phases/P01-save.md) | `v0.1.1` |
| 2 | Data 层 | [`phases/P02-Data层.md`](./phases/P02-Data层.md) | [`phases/P02-save.md`](./phases/P02-save.md) | `v0.1.2` |
| 3 | 保管与取出 | [`phases/P03-保管与取出.md`](./phases/P03-保管与取出.md) | [`phases/P03-save.md`](./phases/P03-save.md) | `v0.1.3` |
| 4 | 指派与双视角 | [`phases/P04-指派与双视角.md`](./phases/P04-指派与双视角.md) | [`phases/P04-save.md`](./phases/P04-save.md) | `v0.1.4` |
| 5 | 付费解锁 | [`phases/P05-付费解锁.md`](./phases/P05-付费解锁.md) | [`phases/P05-save.md`](./phases/P05-save.md) | `v0.1.5` |
| 6 | 设置与备份 | [`phases/P06-设置与备份.md`](./phases/P06-设置与备份.md) | [`phases/P06-save.md`](./phases/P06-save.md) | `v0.1.6` |
| 7 | Catalyst | [`phases/P07-Catalyst.md`](./phases/P07-Catalyst.md) | [`phases/P07-save.md`](./phases/P07-save.md) | `v0.1.7` |
| 8 | 安全审查 | [`phases/P08-安全审查.md`](./phases/P08-安全审查.md) | [`phases/P08-save.md`](./phases/P08-save.md) | `v0.1.8` |

索引：[`05-annotate-branch.md`](./05-annotate-branch.md) · [`15-phase-push.md`](./15-phase-push.md)

## 大阶段收尾

[`10-verify.md`](./10-verify.md) → [`20-push.md`](./20-push.md) → [`30-create-next-branch.md`](./30-create-next-branch.md)（创建 `v0.2`）→ [`40-checkout-next-branch.md`](./40-checkout-next-branch.md)
