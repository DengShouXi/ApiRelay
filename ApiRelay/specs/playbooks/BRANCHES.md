# 分支迭代台账（BRANCHES）

> 中文入口：[`重要说明/索引.md`](./重要说明/索引.md)

**开发小迭代用 Git 分支；商店正式发布才打 `release/N.0.0` tag。**

**硬规则：每一个小阶段写完，都必须打对应小迭代分支并上传（规划线 `plan.N` 与产品线 `v1.N` / `v2.N` / `v3.N` 相同）。**

产品范围与上架时机：[ROADMAP.md](../ROADMAP.md)  
Cursor 规则：[`.cursor/rules/versioning-release.mdc`](../../../.cursor/rules/versioning-release.mdc)

---

## 怎么记

```text
plan.N               规划小迭代
plan                 规划 tip
v{阶段}              产品大阶段 tip（v1 / v2 / v3）
v{阶段}.{小迭代}      产品小迭代（例：v1.13）
v{阶段}.{小迭代}.{热修}  关账 / 上架后热修（例：v1.13.1）
main                 稳定可发布（阶段上架后合并）
release/N.0.0        仅 App Store 上架时打的 tag（不是分支）
```

| 写完什么 | 打开哪个 save | 推到哪个分支 |
|----------|---------------|--------------|
| 规划小阶段 N | `v0-planning/phases/P0N-save.md` | `plan.N`（例：`plan.3`） |
| 产品 Stage1 Phase N | `v1-key-vault/phases/P0N-save.md` | `v1.N` |
| 产品 Stage2 Phase N | `v2-usage-insights/phases/P0N-save.md` | `v2.N` |
| 产品 Stage3 Phase N | `v3-relay-service/phases/P0N-save.md` | `v3.N` |
| **已关账 / 已上架后的修 bug** | [`热修-save.md`](./热修-save.md) | `v{阶段}.{小迭代}.{热修}`（例：`v1.13.1`） |

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

商店热修号：`N.0.1`…（这是 **App Store `MARKETING_VERSION`**，不是 Git 分支名）。  
Git 热修分支：`v{阶段}.{小迭代}.{热修}`（例：`v1.13.1`，先例 `v1.11.1`）。  
**DC-013（V1+V2 捆发）已废止**；以 DC-009（每阶段独立上架）为准。

开发期 Xcode `MARKETING_VERSION` 可暂为 `1.0`；**真正提交 Stage1 审核前**钉死为 `1.0.0` 并打 tag。

---

## 分支 vs tag（禁止把 tag 再建成分支）

同一份提交可以有多个名字。含义不同：

| 名字 | 是什么 | 会不会跟着新 commit 往前走 | 用来干什么 |
|------|--------|----------------------------|------------|
| `v1.N` | **分支** | 关账前会；**关账后冻住** | 开发小迭代里程碑 |
| `v1` / `v2` / `v3` | **分支**（大阶段 tip） | 只前进、不回退 | 当前大阶段最新开发尖端 |
| `main` | **分支** | 下次送审才前进 | 已经当作稳定可发布的线 |
| `release/N.0.0` | **tag（名牌）** | **不会** | 「这一包就是当时上架的商店 N.0.0」 |

因此：

- **不要**再开一条内容与 `v1.13` 相同的分支叫 `release/1.0.0`——tag 已经扮演这个角色，同名分支会和 tag 撞车。  
- **不要**把上架后的修改提交到 `release/1.0.1` 分支。Git 热修用 `v1.13.1`；商店 `1.0.1` 是**以后再送审**时才改的 `MARKETING_VERSION`，那时再打 **tag** `release/1.0.1`。  
- 概念一句话：**分支 = 现在做到哪；tag = 当时上架的是哪一包。**

用户口令与完整步骤：[`热修-save.md`](./热修-save.md)。中文说明：[`重要说明/分支与版本.md`](./重要说明/分支与版本.md)。

---

## 当前分支（本地台账 · 按版本序）

> 更新时间：2026-08-22。下列 `tip` 记的是**该迭代做完代码的那一次提交**；紧随其后「写本文件」的 docs 提交不计入，因此分支真实尖端通常比本列多一格（例：`v1.13` 本列 `37d7bd9`，分支与 tag `release/1.0.0` 实际都在 `539447e`）。这不是台账落后，是记录本记不下它自己造成的那一格。勿把 tip 回退，以免破坏已冻结里程碑。  
> **当前：T062 已执行** — `main` + tag `release/1.0.0`（Stage1 → 商店 **1.0.0**）。  
> **工作分支**：`v1.13.2` 上架后热修；冻结的 `v1.13`、`v1.13.1` 与 tag `release/1.0.0` 不动。  
> **下一步**：继续完成剩余问题；全部确认后再另行授权商店 `1.0.1`、`main` 与 tag `release/1.0.1`。  
> **App Store Connect**：构建上传与「提交审核」须产品负责人在网页完成；内购首次挂审若仍卡住，不阻塞本仓库 `release/1.0.0` 冻结。

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
| `v1.12` | `531234c` | 2026-08-11 03:48 | EN: Phase 12 localization audit — String Catalog en+zh-Hans gaps closed, semantic keys for presets/Custom/tabs, Face ID InfoPlist.xcstrings, App Group store dir + remote-notification; no store metadata. / 中文：小迭代 12 — 本地化验收与补漏（Catalog 缺口清零、预置平台/自定义/Tab 双语、Face ID InfoPlist、模拟器存储目录与 remote-notification）；不含商店元数据 | **已关账**（远程已同步） |
| `v1.13` | `37d7bd9` | 2026-08-12 | EN: Phase 13 closeout + T062 — StoreKit.framework link; Stage1 `main` + tag `release/1.0.0` (store **1.0.0**). ASC binary submit / IAP attach remains on product owner. / 中文：小迭代 13 关账 + T062 — 链接 StoreKit.framework；仓库侧建立 `main` 与 `release/1.0.0`（商店 **1.0.0**）。App Store Connect 选构建/提交审核及内购挂审仍由产品负责人处理 | **已关账**；tag `release/1.0.0` |
| `v1.13.1` | `bc8b2fa` | 2026-08-22 | EN: Hotfix snapshot through 2026-08-21 22:26 CST — strengthened vault privacy and local Keychain duplicate detection; added browse/edit key details, avatars, vault-wide search, sorting/reordering, recycle-bin batch actions, expanded presets, backup import/export with default passphrase, unified Settings chrome, adjustable Mac columns, iCloud sync status/manual metadata submission, and CloudKit preference hang fixes. Excludes later App Lock, clipboard termination handling and subsequent UI refinements. / 中文：截至 2026-08-21 22:26 的热修快照 — 加强密钥隐私与本机 Keychain 重复检测；新增密钥浏览/编辑、头像、保险库综合搜索、排序与拖拽、回收站批量操作；扩充预置；完善备份导入导出和默认口令；统一设置界面；恢复 Mac 三栏调节；增加 iCloud 同步状态与立即提交元数据；修复 CloudKit 偏好写入卡死。不含之后的 App 锁、退出时剪贴板处理及后续界面微调 | 商店号仍为 **1.0.0**；不覆盖 `v1.13`，不移动 `main` / tag |
| `v1.13.2` | `60f5915` | 2026-08-22 | EN: Hotfix 13.2 — App Lock made real: "require authentication to open", auto-lock timeout and hide-in-app-switcher now drive actual behaviour via `AppLockSession` (pure decision) + `AppPrivacyController` (lifecycle, gate, switcher cover) + `AppLockCoverView`. Master-password policy no longer raises the system iPhone-passcode sheet; unlocking uses the in-app password screen. Master-password creation rules are listed and validated rule by rule. Clipboard: iPhone retries `setItems` with the same `.expirationDate` / `.localOnly` options instead of `pb.string` (which wiped system expiry); Mac still writes `.string` so other apps can paste (no system expiry). In-app timer plus ⌘Q `applicationWillTerminate` (`changeCount`) clear only if still ours; force-quit and crashes cannot. Copy confirmation and Settings state the real timeout and this Mac limit in plain language; Mac clipboard-history tools are out of reach. Mac three-column drops the sidebar-hidden branch and the orphaned `MacSidebarChrome.swift` (which referenced a removed symbol and broke the iOS build) is deleted. / 中文：热修 13.2 — App 锁落地：「打开 App 需要身份确认」「自动锁定时长」「在应用切换器中隐藏」由 `AppLockSession`（纯决策）+ `AppPrivacyController`（生命周期、门闩、切换器遮罩）+ `AppLockCoverView` 驱动真实行为；验证方式为主密码时不再弹系统「iPhone 密码」，改走应用内解锁页；主密码创建规则逐条呈现并逐条校验；剪贴板：iPhone 补写改走同一份 `setItems`，不再用 `pb.string` 冲掉系统过期与仅本机；Mac 为保粘贴仍写 `.string`（无系统过期）。App 开着按时清，⌘Q 按 `changeCount` 尽力清，强制退出/崩溃清不了；复制提示与设置用真实时长，并写明 Mac 局限与剪贴板历史工具清不掉；Mac 三栏去掉侧栏隐藏分支，删除已失去引用、且引用已删符号导致 iOS 编译失败的 `MacSidebarChrome.swift` | 商店号仍为 **1.0.0**；不覆盖 `v1.13` / `v1.13.1`，不移动 `main` / tag |
| `v1` | `60f5915` | 2026-08-22 | EN: Stage1 tip advances to the v1.13.2 hotfix; release references stay frozen. / 中文：大阶段 1 tip 前进到 `v1.13.2` 热修；已发布引用保持冻结 | `main` / `release/1.0.0` 不动 |
| `main` | `37d7bd9` | 2026-08-12 | EN: First stable publish branch — Stage1 **1.0.0**. / 中文：首个稳定发布分支 — Stage1 **1.0.0** | 由 `v1` 建立；tag `release/1.0.0` |

### 保护约定（避免破坏分支）

1. **小迭代分支是冻结里程碑**：`v1.N` / `plan.N` tip 对齐后，不要用新提交「盖掉」旧 tip，除非明确做热修分支（如 `v1.11.1` / `v1.13.1`）。  
2. **大阶段 tip**（`v1` / `v2` / `plan`）只前进、不回退。  
3. **同 tip 不代表可合并删除**：例如 `v1.4`–`v1.7` 同 tip，仍各自保留，对应阶段台账。  
4. 远程只保留**现行名**；旧名 `v0.*` 仅作历史对照，清理后勿再建。  
5. **禁止**创建 `release/*` **分支**（`release/N.0.0` 只允许作为上架 **tag**）。  
6. 上架后热修默认**不**移动 `main`、**不**改 `MARKETING_VERSION`、**不**打新 `release/*` tag；下次真送审时另授权。

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
- 上架后热修保存并上传：[`热修-save.md`](./热修-save.md)  
- 总览：[`README.md`](./README.md)
