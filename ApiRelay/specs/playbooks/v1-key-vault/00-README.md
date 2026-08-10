# V1 — 密钥保险库 Playbook

**大阶段分支**：`v1`  
**当前小迭代**：`v1.12`（Stage1 代码调整 / 体验优化；接 `v1.11` / 热修 `v1.11.1`）  
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
| 9 | [`P09-可用性加固.md`](./phases/P09-可用性加固.md) | [`P09-save.md`](./phases/P09-save.md) → `v1.9`（已上传；文档补档） | `V1/Phase09_UXHardening/` · 验收：[`P09-验收清单.md`](./phases/P09-验收清单.md) |
| 10 | [`P10-UI重设计.md`](./phases/P10-UI重设计.md) | [`P10-save.md`](./phases/P10-save.md) → `v1.10`（已冻结） | 验收：[`P10-验收清单.md`](./phases/P10-验收清单.md) |
| 11 | [`P11-AppIcon与资源.md`](./phases/P11-AppIcon与资源.md) | [`P11-save.md`](./phases/P11-save.md) → `v1.11`（已冻结；热修 `v1.11.1`） | `V1/Phase11_AppIconAssets/` · 验收：[`P11-验收清单.md`](./phases/P11-验收清单.md) |
| 12 | （待补 `P12-*.md`） | → `v1.12`（**当前**） | `V1/Phase12_*`（待建） |

收尾（上架准备）：`10-verify` → 准备 **1.0.0** → `20-push`。大阶段 2：`30` / `40` → [`../v2-usage-insights/00-README.md`](../v2-usage-insights/00-README.md)。
