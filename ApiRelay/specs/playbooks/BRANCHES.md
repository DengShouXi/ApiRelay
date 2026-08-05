# 分支迭代台账（统一规则）

**开发小迭代用 Git 分支；商店正式发布才打 `release/N.0.0` tag。**

**硬规则：每一个小阶段写完，都必须打对应小迭代分支并上传（规划线 `plan.N` 与产品线 `v1.N` / `v2.N` / `v3.N` 相同）。**

产品范围与上架时机：[ROADMAP.md](../ROADMAP.md)  
Cursor 规则：[`.cursor/rules/versioning-release.mdc`](../../../.cursor/rules/versioning-release.mdc)

---

## 怎么记

```text
plan.N          规划小迭代
plan            规划 tip
v{阶段}         产品大阶段 tip（v1 / v2 / v3）
v{阶段}.{小迭代} 产品小迭代（例：v1.5）
main            稳定可发布（阶段上架后合并）
release/N.0.0   仅 App Store 上架时打的 tag（Stage1→1.0.0，Stage2→2.0.0，Stage3→3.0.0）
```

| 写完什么 | 打开哪个 save | 推到哪个分支 |
|----------|---------------|--------------|
| 规划小阶段 N | `v0-planning/phases/P0N-save.md` | `plan.N`（例：`plan.3`） |
| 产品 Stage1 Phase N | `v1-key-vault/phases/P0N-save.md` | `v1.N` |
| 产品 Stage2 Phase N | `v2-usage-insights/phases/P0N-save.md` | `v2.N` |
| 产品 Stage3 Phase N | `v3-relay-service/phases/P0N-save.md` | `v3.N` |

每次 save 还必须：更新本文件 **English → 简体中文** 备注。

### 旧名对照（历史远程可保留，不再新建）

| 旧名 | 现行名 |
|------|--------|
| `v0.0.N` / `v0.0` | `plan.N` / `plan` |
| `v0.1.N` / `v0.1` | `v1.N` / `v1` |
| `v0.2.N` / `v0.2` | `v2.N` / `v2` |
| `v0.3.N` / `v0.3` | `v3.N` / `v3` |
| 文档里的 Git 分支 `001-key-vault` 等 | 改为 `v1` / `v2` / `v3`（`specs/001-key-vault/` 仍是目录路径） |

---

## 上架与 `MARKETING_VERSION`

| 阶段验收 | 商店版本 | Tag |
|----------|----------|-----|
| Stage 1 | `1.0.0` | `release/1.0.0` |
| Stage 2 | `2.0.0` | `release/2.0.0` |
| Stage 3 | `3.0.0` | `release/3.0.0` |

热修：`N.0.1`…。**DC-013（V1+V2 捆发）已废止**；以 DC-009（每阶段独立上架）为准。

开发期 Xcode `MARKETING_VERSION` 可暂为 `1.0`；**真正提交 Stage1 审核前**钉死为 `1.0.0` 并打 tag。

---

## 当前分支

| 分支 | English | 简体中文 |
|------|---------|----------|
| `plan.1`（旧 `v0.0.1`） | Earliest engineering baseline | 最初工程基线 |
| `plan.2` / `plan`（旧 `v0.0.2` / `v0.0`） | Specs/planning freeze | 规格/规划冻住 |
| `v1`（旧 `v0.1`） | Stage-1 workline tip | 大阶段 1 尖端 |
| `v1.1` | Phase 1 engineering scaffold | 小迭代 1 — 工程配置 |
| `v1.2` | Phase 2 Data layer (Keychain actor, 10 models, repos, PresetCatalog). T014b deferred. | 小迭代 2 — Data 层；T014b 延期 |
| `v1.3` | Phase 3 vault: RevealGate, MasterPassword, clipboard, KeyVaultService, Vault UI | 小迭代 3 — 保管与取出 |
| `v1.4` | Phase 4 grouping: shared KeyGrouping, consumer tools CRUD/seed, dual perspective UI, custom platform | 小迭代 4 — 指派与双视角 |
| `v1.5` | Phase 5 entitlements: StoreKit 2 service, DEBUG override, restore, paywall, StoreKit config | 小迭代 5 — 付费解锁 |
| `v1.6` | Phase 6 settings: PreferencesService, SecureBackup, eraseAllUserData, Settings UI | 小迭代 6 — 设置与加密备份 |
| `v1.7` | Phase 7 Catalyst window size, Commands, context menus | 小迭代 7 — Catalyst |
| `v1.8` | Phase 8 security review + Stage1 engineering closeout. Store materials prepared for **1.0.0** when shipping. T014b may await Developer Program. | 小迭代 8 — 安全审查；商店材料随 Stage1→1.0.0 |
| `v1.9` | UX hardening + **T014b Checkpoint 2b**：CloudKit Production 8 表与 §7.1 预留字段已 Deploy；DEBUG `CloudKitSchemaBootstrap` 一次性逼 schema。Checkout `v1.9`。 | 小迭代 9 — 可用性加固 + CloudKit Production 闸门通过 |
| `v1.10` | Phase 10 UI redesign: 4-tab IA (platform / consumer / trash / settings), settings cards, assign sheet, key `sortOrder` + Mac NSTableView reorder (drag polish still imperfect), iCloud sync sheet. Frozen tip after push. | 小迭代 10 — UI 重设计：底栏四 Tab、设置卡片、指派 sheet、密钥分区排序（Mac 拖拽手感仍有瑕疵）、iCloud 同步说明。已冻结上传。 |
| `v1.11` | Stage1 continuation tip after UI redesign. **current**. Checkout `v1.11` for next coding. | 小迭代 11 — UI 重设计后的 Stage1 继续开发。**当前**。取 `v1.11` 继续编码。 |
| `v2` | Stage-2 workline tip (usage insights). Open after Stage1 ship readiness (`10-verify` / `20-push`), not required for `v1.11` coding. | 大阶段 2 尖端（用量看板）。Stage1 上架准备就绪后再开；`v1.11` 编码不必先开 `v2`。 |

---

## 测试隔离

| 路径 | 说明 |
|------|------|
| `ApiRelay/ApiRelay/` | 正式代码 |
| `ApiRelay/ApiRelayTests/V0/Phase*/` | 规划迭代（对应 `plan.N`） |
| `ApiRelay/ApiRelayTests/V1/Phase*/` | 与 `v1.N` 对应 |
| `ApiRelay/ApiRelayTests/V2/Phase*/` | 与 `v2.N` 对应 |
| `ApiRelay/ApiRelayTests/V3/Phase*/` | 与 `v3.N` 对应 |
| `ApiRelay/DebugScratch/` | 本地乱写，不上传 |

---

## Playbook 入口

- 规划：[`v0-planning/00-README.md`](./v0-planning/00-README.md)  
- Stage1：[`v1-key-vault/00-README.md`](./v1-key-vault/00-README.md)  
- Stage2 / Stage3：对应目录 `00-README.md`  
- 总览：[`README.md`](./README.md)
