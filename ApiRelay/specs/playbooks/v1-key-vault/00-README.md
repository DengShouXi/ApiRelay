# V1 — 密钥保险库 Playbook

**大阶段分支**：`v1`  
**当前小迭代**：`v1.9`（可用性加固；下一 `v1.10`）  
**上架目标**：Stage1 验收后 App Store **1.0.0**（tag `release/1.0.0`）  
台账：[BRANCHES.md](../BRANCHES.md) · 测试：[ApiRelayTests/README.md](../../../ApiRelayTests/README.md)

记法：`v1.N` = Stage1 小迭代（开发用分支；商店发布才打 `release/1.0.0`）。

| Phase | 实现 | 保存→小迭代分支 | 测试目录 |
|-------|------|-----------------|----------|
| 1 | [`P01-工程配置.md`](./phases/P01-工程配置.md) | [`P01-save.md`](./phases/P01-save.md) → `v1.1` | `V1/Phase01_Setup/` |
| 2 | [`P02-Data层.md`](./phases/P02-Data层.md) | [`P02-save.md`](./phases/P02-save.md) → `v1.2` | `V1/Phase02_Data/` |
| 3 | [`P03-保管与取出.md`](./phases/P03-保管与取出.md) | [`P03-save.md`](./phases/P03-save.md) → `v1.3` | `V1/Phase03_Vault/` |
| 4 | [`P04-指派与双视角.md`](./phases/P04-指派与双视角.md) | [`P04-save.md`](./phases/P04-save.md) → `v1.4` | `V1/Phase04_Grouping/` |
| 5 | [`P05-付费解锁.md`](./phases/P05-付费解锁.md) | [`P05-save.md`](./phases/P05-save.md) → `v1.5` | `V1/Phase05_Entitlement/` |
| 6 | [`P06-设置与备份.md`](./phases/P06-设置与备份.md) | [`P06-save.md`](./phases/P06-save.md) → `v1.6` | `V1/Phase06_Settings/` |
| 7 | [`P07-Catalyst.md`](./phases/P07-Catalyst.md) | [`P07-save.md`](./phases/P07-save.md) → `v1.7` | `V1/Phase07_Catalyst/` |
| 8 | [`P08-安全审查.md`](./phases/P08-安全审查.md) | [`P08-save.md`](./phases/P08-save.md) → `v1.8` | `V1/Phase08_Security/` |

收尾：`10-verify` → 准备 **1.0.0** 上架 → `20-push` →（上架后）`30`（开 `v2`）→ `40`。
