# V1 — 密钥保险库 Playbook

**当前 Git 线**：`v0.1.x`（产品第 1 大阶段；命名见 [BRANCHES.md](../BRANCHES.md)）  
**规格**：[`specs/001-key-vault/`](../../001-key-vault/)  
**任务权威**：[`tasks.md`](../../001-key-vault/tasks.md)

## 一句话

给 API 密钥做一个比「记在备忘录里」安全得多的保管与分发工具。**完全不联网调用任何上游平台接口。**

## 明确不做（界面也不出入口）

用量、余额、适配器、探活、签发/作废、关系图、通知、中转。

## 8 个阶段 ↔ 分支第三位

| Phase | 主题 | 实现提示词 | 完成后里程碑分支 |
|-------|------|------------|------------------|
| 1 | 工程配置 | [`phases/P01-工程配置.md`](./phases/P01-工程配置.md) | `v0.1.1` |
| 2 | Data 层 | [`phases/P02-Data层.md`](./phases/P02-Data层.md) | `v0.1.2` |
| 3 | US1 保管与取出 | [`phases/P03-保管与取出.md`](./phases/P03-保管与取出.md) | `v0.1.3` |
| 4 | US2 指派与双视角 | [`phases/P04-指派与双视角.md`](./phases/P04-指派与双视角.md) | `v0.1.4` |
| 5 | US5 付费解锁 | [`phases/P05-付费解锁.md`](./phases/P05-付费解锁.md) | `v0.1.5` |
| 6 | US6 设置与备份 | [`phases/P06-设置与备份.md`](./phases/P06-设置与备份.md) | `v0.1.6` |
| 7 | Mac Catalyst | [`phases/P07-Catalyst.md`](./phases/P07-Catalyst.md) | `v0.1.7` |
| 8 | 安全审查 | [`phases/P08-安全审查.md`](./phases/P08-安全审查.md) | `v0.1.8` |

每个 Phase 结束：`05-annotate-branch.md` → `15-phase-push.md`。

## 大阶段收尾

1. [`10-verify.md`](./10-verify.md)  
2. [`20-push.md`](./20-push.md)  
3. [`30-create-next-branch.md`](./30-create-next-branch.md) → `v0.2.1`  
4. [`40-checkout-next-branch.md`](./40-checkout-next-branch.md)  
