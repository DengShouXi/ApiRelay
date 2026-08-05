# V2 — 用量看板与关系图 Playbook

**大阶段分支**：`v2`（做到本大阶段再创建）  
**小迭代分支**：`v2.1` … `v2.8`（每完成一个 Phase 推一个）  
**上架目标**：Stage2 验收后 App Store **2.0.0**（tag `release/2.0.0`）  
台账：[BRANCHES.md](../BRANCHES.md) · 测试：`ApiRelayTests/V2/Phase0N_*/`

记法：`v2.N` = Stage2 小迭代。

| Phase | 主题 | 实现 | 保存→小迭代分支 | 测试目录 |
|-------|------|------|-----------------|----------|
| 1 | 规格与网络骨架 | [`P01-规格与网络骨架.md`](./phases/P01-规格与网络骨架.md) | [`P01-save.md`](./phases/P01-save.md) → `v2.1` | `Phase01_Network/` |
| 2 | 管理凭证与适配器 | [`P02-管理凭证与适配器.md`](./phases/P02-管理凭证与适配器.md) | [`P02-save.md`](./phases/P02-save.md) → `v2.2` | `Phase02_Adapters/` |
| 3 | 用量与余额 | [`P03-用量与余额.md`](./phases/P03-用量与余额.md) | [`P03-save.md`](./phases/P03-save.md) → `v2.3` | `Phase03_Usage/` |
| 4 | 密钥探活 | [`P04-密钥探活.md`](./phases/P04-密钥探活.md) | [`P04-save.md`](./phases/P04-save.md) → `v2.4` | `Phase04_Health/` |
| 5 | 签发与作废 | [`P05-签发与作废.md`](./phases/P05-签发与作废.md) | [`P05-save.md`](./phases/P05-save.md) → `v2.5` | `Phase05_Issuance/` |
| 6 | 关系图 | [`P06-关系图.md`](./phases/P06-关系图.md) | [`P06-save.md`](./phases/P06-save.md) → `v2.6` | `Phase06_Graph/` |
| 7 | 加密传递与通知 | [`P07-加密传递与通知.md`](./phases/P07-加密传递与通知.md) | [`P07-save.md`](./phases/P07-save.md) → `v2.7` | `Phase07_TransferNotify/` |
| 8 | 上架与收尾 | [`P08-上架与收尾.md`](./phases/P08-上架与收尾.md) | [`P08-save.md`](./phases/P08-save.md) → `v2.8` | `Phase08_Store/` |

收尾：`10-verify` → **2.0.0** 上架 → `20-push` → `30`（创建大阶段 `v3`）→ `40`。
