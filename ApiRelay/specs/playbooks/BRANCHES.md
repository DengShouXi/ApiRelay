# 分支迭代台账（统一规则）

**只用一种结构：三层都是 Git 分支，按小迭代往前走。不用 tag 做版本里程碑。**

**硬规则：每一个小阶段写完，都必须打对应小迭代分支并上传（规划线 `v0.0.N` 与产品线 `v0.1.N` / `v0.2.N` / `v0.3.N` 相同）。**

产品范围：[ROADMAP.md](../ROADMAP.md)

---

## 怎么记

```text
v0 . 大阶段 . 小迭代
      0 规划
      1 密钥库
      2 用量
      3 中转
```

| 写完什么 | 打开哪个 save | 推到哪个分支 |
|----------|---------------|--------------|
| 规划小阶段 N | `v0-planning/phases/P0N-save.md` | `v0.0.N`（例：`v0.0.3`） |
| 产品 V1 Phase N | `v1-key-vault/phases/P0N-save.md` | `v0.1.N` |
| 产品 V2 Phase N | `v2-usage-insights/phases/P0N-save.md` | `v0.2.N` |
| 产品 V3 Phase N | `v3-relay-service/phases/P0N-save.md` | `v0.3.N` |

每次 save 还必须：更新本文件 **English → 简体中文** 备注。

---

## 当前分支

| 分支 | English | 简体中文 |
|------|---------|----------|
| `v0.0.1` | Earliest engineering baseline | 最初工程基线 |
| `v0.0.2` / `v0.0` | Specs/planning freeze | 规格/规划冻住 |
| `v0.1` | Stage-1 workline tip | 大阶段 1 尖端 |
| `v0.1.1` | Phase 1 engineering scaffold | 小迭代 1 — 工程配置 |
| `v0.1.2` | Phase 2 Data layer (Keychain actor, 10 models, repos, PresetCatalog). T014b deferred. | 小迭代 2 — Data 层；T014b 延期 |
| `v0.1.3` | Phase 3 vault: RevealGate, MasterPassword, clipboard, KeyVaultService, Vault UI | 小迭代 3 — 保管与取出 |
| `v0.1.4` | Phase 4 grouping: shared KeyGrouping, consumer tools CRUD/seed, dual perspective UI, custom platform | 小迭代 4 — 指派与双视角 |
| `v0.1.5` | Phase 5 entitlements: StoreKit 2 service, DEBUG override, restore, paywall, StoreKit config (`com.apirelay.iap.unlimited_keys`, family shareable) | 小迭代 5 — 付费解锁 |
| `v0.1.6` | Phase 6 settings: PreferencesService (FR-060 split), SecureBackup AES-GCM with purpose/scope, eraseAllUserData, Settings UI | 小迭代 6 — 设置与加密备份 |
| `v0.1.7` | Phase 7 Catalyst: default 900×700 / min 800×600, Commands ⌘, / ⌘N, context menus, biometricOnly auto-disable | 小迭代 7 — Catalyst |
| `v0.1.8` | Phase 8 security review automation + V1 engineering closeout. **current**. T062 main merge/tag awaiting explicit auth. T014b still deferred until Developer Program. | 小迭代 8 — 安全审查收尾（**当前**）。T062 待授权；T014b 仍延期 |

---

## 测试隔离

| 路径 | 说明 |
|------|------|
| `ApiRelay/ApiRelay/` | 正式代码 |
| `ApiRelay/ApiRelayTests/V0/Phase*/` | 规划迭代（可空） |
| `ApiRelay/ApiRelayTests/V1/Phase*/` | 与 `v0.1.N` 对应 |
| `ApiRelay/DebugScratch/` | 本地乱写，不上传 |

---

## Playbook 入口

- 规划：[`v0-planning/00-README.md`](./v0-planning/00-README.md)  
- V1：[`v1-key-vault/00-README.md`](./v1-key-vault/00-README.md)  
- V2 / V3：对应目录 `00-README.md`  
- 总览：[`README.md`](./README.md)
