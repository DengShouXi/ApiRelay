# V1 — 密钥保险库 Playbook

**大阶段分支**：`v1`  
**当前小迭代**：**`v1.13` 已关账**；仓库侧 T062 已打 tag `release/1.0.0`。上架后修 bug → [`../热修-save.md`](../热修-save.md)（`v1.13.1`），不要盖 `v1.13`。  
**上架目标**：Stage1 App Store **1.0.0**（tag `release/1.0.0` 已打；ASC 提交由产品负责人在网页完成）  
台账：[BRANCHES.md](../BRANCHES.md) · 测试：[ApiRelayTests/README.md](../../../ApiRelayTests/README.md) · 中文入口：[重要说明/阶段1-密钥库.md](../重要说明/阶段1-密钥库.md)

记法：`v1.N` = Stage1 小迭代（开发用分支；商店发布才打 `release/1.0.0` tag）。

## 端到端顺序（勿跳步）

```text
P01…P12 实现小迭代（各 P0N → P0N-save → v1.N）
  → P13 上架材料 T063–T066（不上架）
  → P13-save → v1.13 + tip v1
  → 10-verify（Stage1 总验收）
  → 12-release-T062（须明确授权：main + release/1.0.0 + 提交审核）
  → 20-push（大阶段收尾核对）
  → 30-create-next-branch（建 v2 tip）
  → 40-checkout-next-branch → ../v2-usage-insights/
```

| 收尾文件 | 作用 |
|----------|------|
| [`10-verify.md`](./10-verify.md) | Stage1 总验收；**不**打 tag |
| [`12-release-T062.md`](./12-release-T062.md) | **T062** 发布；无授权句禁止执行 |
| [`20-push.md`](./20-push.md) | 确认 `main` / `release/1.0.0` / 台账后才能开 V2 |
| [`30-create-next-branch.md`](./30-create-next-branch.md) | 创建大阶段 tip `v2`（不建 `v2.1`） |
| [`40-checkout-next-branch.md`](./40-checkout-next-branch.md) | 切到 `v2` 并打开 Stage2 README |
| [`../热修-save.md`](../热修-save.md) | 上架后 / 关账后修 bug：开 `v1.13.1` 并上传；不开 `release/*` 分支 |

**职责分割**：P08 = 安全审查 T056–T061；P13 = 商店材料 T063–T066；T062 = 仅发布动作。  
**Checkpoint 2b（T014b）** 已在 `v1.9` 关闭，是同步硬门槛，不是「未 Deploy 不得写 Phase 3」。

## 小迭代表

| Phase | 实现 | 保存→小迭代分支 | 测试 / 验收 |
|-------|------|-----------------|-------------|
| 1 | [`P01-工程配置.md`](./phases/P01-工程配置.md) | [`P01-save.md`](./phases/P01-save.md) → `v1.1` | `V1/Phase01_Setup/` |
| 2 | [`P02-Data层.md`](./phases/P02-Data层.md) | [`P02-save.md`](./phases/P02-save.md) → `v1.2` | `V1/Phase02_Data/` |
| 3 | [`P03-保管与取出.md`](./phases/P03-保管与取出.md) | [`P03-save.md`](./phases/P03-save.md) → `v1.3` | `V1/Phase03_Vault/` |
| 4 | [`P04-指派与双视角.md`](./phases/P04-指派与双视角.md) | [`P04-save.md`](./phases/P04-save.md) → `v1.4` | `V1/Phase04_Grouping/` |
| 5 | [`P05-付费解锁.md`](./phases/P05-付费解锁.md) | [`P05-save.md`](./phases/P05-save.md) → `v1.5` | `V1/Phase05_Entitlement/` |
| 6 | [`P06-设置与备份.md`](./phases/P06-设置与备份.md) | [`P06-save.md`](./phases/P06-save.md) → `v1.6` | `V1/Phase06_Settings/` |
| 7 | [`P07-Catalyst.md`](./phases/P07-Catalyst.md) | [`P07-save.md`](./phases/P07-save.md) → `v1.7` | `V1/Phase07_Catalyst/` |
| 8 | [`P08-安全审查.md`](./phases/P08-安全审查.md) | [`P08-save.md`](./phases/P08-save.md) → `v1.8` | `V1/Phase08_Security/`（**不含**商店材料） |
| 9 | [`P09-可用性加固.md`](./phases/P09-可用性加固.md) | [`P09-save.md`](./phases/P09-save.md) → `v1.9` | 验收：[`P09-验收清单.md`](./phases/P09-验收清单.md) |
| 10 | [`P10-UI重设计.md`](./phases/P10-UI重设计.md) | [`P10-save.md`](./phases/P10-save.md) → `v1.10` | [`P10-验收清单.md`](./phases/P10-验收清单.md) |
| 11 | [`P11-AppIcon与资源.md`](./phases/P11-AppIcon与资源.md) | [`P11-save.md`](./phases/P11-save.md) → `v1.11` | [`P11-验收清单.md`](./phases/P11-验收清单.md)；热修 `v1.11.1` |
| 12 | [`P12-本地化验收.md`](./phases/P12-本地化验收.md) | [`P12-save.md`](./phases/P12-save.md) → `v1.12`（**已关账**） | [`P12-验收清单.md`](./phases/P12-验收清单.md) |
| 13 | [`P13-上架材料.md`](./phases/P13-上架材料.md) | [`P13-save.md`](./phases/P13-save.md) → `v1.13`（**已关账**） | [`P13-验收清单.md`](./phases/P13-验收清单.md) · [`P13-人工操作指南/`](./phases/P13-人工操作指南/00-README.md) · [`store-drafts/v1.13/`](./store-drafts/v1.13/) |

小迭代上传索引（节选）：[`05-annotate-branch.md`](./05-annotate-branch.md)。
