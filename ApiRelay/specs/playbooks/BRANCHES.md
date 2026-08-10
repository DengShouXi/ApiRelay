# 分支迭代台账（BRANCHES）

> 中文入口：[`重要说明/索引.md`](./重要说明/索引.md)

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

### 旧名对照（仅历史对照，远程旧名应删除、勿再建）

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

## 当前分支（本地台账 · 按版本序）

> 更新时间：2026-08-11。下列 tip / 时间为各分支**尖端提交**；勿把 tip 回退，以免破坏已冻结里程碑。  
> **当前工作分支：`v1.12`（已关账）**；下一开工：从 `v1` 拉 **`v1.13`** 做上架材料 T063–T066。

| 分支 | tip | tip 时间 | 主要做了什么（简体中文） | 备注 |
|------|-----|----------|--------------------------|------|
| `plan.1` | `2cf6803` | 2026-08-04 15:53 | 最初工程基线：Mac SwiftUI 工程与 SpecKit 工具链落地 | 旧名 `v0.0.1` |
| `plan` | `a62244d` | 2026-08-04 21:47 | 规划 tip：规格与规则快照后冻住，准备进入实现 playbook | 旧名 `v0.0`；与 `plan.2` 同 tip |
| `plan.2` | `a62244d` | 2026-08-04 21:47 | 规划小迭代 2：规格/规划冻住 | 旧名 `v0.0.2`；与 `plan` 同 tip |
| `v1.1` | `df0b485` | 2026-08-04 22:14 | 小迭代 1 — 工程配置；明确每个小阶段必须打分支并上传 | 旧名 `v0.1.1` |
| `v1.2` | `8e85a0c` | 2026-08-04 22:43 | 小迭代 2 — Data 层（Keychain actor、模型/仓库、PresetCatalog）；T014b 延期 | 旧名 `v0.1.2` |
| `v1.3` | `536ffe7` | 2026-08-04 22:59 | 小迭代 3 — 保管与取出（RevealGate、主密码、剪贴板、KeyVaultService、Vault UI） | 旧名 `v0.1.3` |
| `v1.4` | `c890219` | 2026-08-04 23:10 | 小迭代 4 — 指派与双视角（分组、使用方工具、自定义平台等）；与 5–7 同 tip | 旧名 `v0.1.4`；连续完成 Phase 4–7 后冻结 |
| `v1.5` | `c890219` | 2026-08-04 23:10 | 小迭代 5 — 付费解锁（StoreKit 2、DEBUG 覆盖、恢复购买、付费墙） | 旧名 `v0.1.5`；与 `v1.4`–`v1.7` 同 tip |
| `v1.6` | `c890219` | 2026-08-04 23:10 | 小迭代 6 — 设置与加密备份（偏好、SecureBackup、清空用户数据） | 旧名 `v0.1.6`；与 `v1.4`–`v1.7` 同 tip |
| `v1.7` | `c890219` | 2026-08-04 23:10 | 小迭代 7 — Catalyst（窗口尺寸、Commands、上下文菜单） | 旧名 `v0.1.7`；tip 含后续 StoreKit/T014b 说明修复 |
| `v2` | `44468ce` | 2026-08-04 23:07 | 大阶段 2 tip（用量看板）工线已开；Stage1 上架准备就绪后再深做 | 旧名 `v0.2` |
| `v1.8` | `d7bcbea` | 2026-08-05 10:53 | 小迭代 8 — 安全审查收口；开通 CloudKit + Keychain 同步（Developer 账号后） | 旧名 `v0.1.8` |
| `v1.9` | `32318c2` | 2026-08-05 16:21 | 小迭代 9 — 可用性加固（多钥/回收站/双视角）+ T014b CloudKit Production 闸门 | 现行 tip（含改名后文档提交）；勿回退到更旧的 `7c77778` |
| `v1.10` | `8a06e9e` | 2026-08-05 23:34 | 小迭代 10 — UI 重设计：四 Tab、设置卡片、指派 sheet、密钥排序、iCloud 说明；已冻结 | |
| `v1.11` | `9a1bde1` | 2026-08-11 01:57 | 小迭代 11 — App Icon 全尺寸、SF Symbol/PresetCatalog、Accent 同源、使用方图标回填；已冻结 | |
| `v1.11.1` | `7eabc59` | 2026-08-11 02:19 | 热修 11.1 — 强制刷新 App Icon 槽；底栏改为正/负电荷符号（⊕/⊖） | 热修冻结 tip；其后文档在 `v1.12` |
| `v1.12` | `94f2942` | 2026-08-11 03:48 | EN: Phase 12 localization audit — String Catalog en+zh-Hans gaps closed, semantic keys for presets/Custom/tabs, Face ID InfoPlist.xcstrings, App Group store dir + remote-notification; no store metadata. / 中文：小迭代 12 — 本地化验收与补漏（Catalog 缺口清零、预置平台/自定义/Tab 双语、Face ID InfoPlist、模拟器存储目录与 remote-notification）；不含商店元数据 | **已关账** |
| `v1.13` | — | — | EN: Phase 13 Stage1 store materials (T063–T066); playbook ready; branch not opened until kickoff. / 中文：小迭代 13 — 上架材料（T063–T066）；playbook 已就绪，开工时再从 `v1` 拉分支 | **下一开工**；勿与 T062 混做 |
| `v1` | `94f2942` | 2026-08-11 03:48 | EN: Stage1 tip follows v1.12; next = open v1.13 for T063–T066. / 中文：大阶段 1 tip（跟随 `v1.12`）；下一步开 `v1.13` 上架材料 | 推荐作为仓库默认分支；勿回退到旧名 `v0.1` tip |

### 保护约定（避免破坏分支）

1. **小迭代分支是冻结里程碑**：`v1.N` / `plan.N` tip 对齐后，不要用新提交「盖掉」旧 tip，除非明确做热修分支（如 `v1.11.1`）。  
2. **大阶段 tip**（`v1` / `v2` / `plan`）只前进、不回退。  
3. **同 tip 不代表可合并删除**：例如 `v1.4`–`v1.7` 同 tip，仍各自保留，对应阶段台账。  
4. 远程只保留**现行名**；旧名 `v0.*` 仅作历史对照，清理后勿再建。

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
