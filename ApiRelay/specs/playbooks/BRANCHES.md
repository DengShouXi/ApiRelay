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
| `v0.0.2` / `v0.0` | Specs/planning freeze @ ~20:47 | 规格/规划冻住 |
| `v0.0.3` | （尚未创建）Next planning iteration when needed | 下一规划小迭代：写完再用 P03-save 上传 |
| `v0.1` | Stage-1 workline tip | 大阶段 1 尖端 |
| `v0.1.1` | Phase 1 iteration — engineering scaffold | 小迭代 1 — 工程配置 |
| `v0.1.2` | Phase 2 Data layer @ tip of prior iteration. Actor KeychainStore, ten SwiftData models, repositories, PresetCatalog. No vault UI. | 小迭代 2 — Data 层。KeychainStore、十实体、Repository、PresetCatalog。无保管 UI。 |
| `v0.1.3` | Phase 3 vault — **current work**. RevealGate (4 policies), MasterPassword PBKDF2, SecureClipboard, KeyVaultService (quota/soft-delete/reveal/copy), Vault UI. Local store + non-sync Keychain until Developer Program / T014b. | 小迭代 3 — 保管与取出（**当前**）。四档门闩、主密码、剪贴板、KeyVaultService、Vault UI。在开通开发者账号/T014b 前用本机存储且 Keychain 暂不同步。 |

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
