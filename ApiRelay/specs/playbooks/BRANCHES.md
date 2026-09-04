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

> 更新时间：2026-09-04。下列 `tip` 记的是**该迭代做完代码的那一次提交**；紧随其后「写本文件」的 docs 提交不计入，因此分支真实尖端通常比本列多一格（例：`v1.13` 本列 `37d7bd9`，分支与 tag `release/1.0.0` 实际都在 `539447e`）。这不是台账落后，是记录本记不下它自己造成的那一格。勿把 tip 回退，以免破坏已冻结里程碑。  
> **当前：T062 已执行** — `main` + tag `release/1.0.0`（Stage1 → 商店 **1.0.0**）。  
> **工作分支**：仍是 `v1.13.2` 上架后热修（2026-09-04 续：**H4 补失败预案已执行**——生物识别死局出口、无明文可辨、备份空明文计数）；冻结的 `v1.13`、`v1.13.1` 与 tag `release/1.0.0` 不动。  
> **下一步**：备案、商店热修 1.0.1；**99 总验收**；旁账（目录改名 / `tools/` / ZL01 重排）。全部确认后再另行授权商店 `1.0.1`、`main` 与 tag `release/1.0.1`。  
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
| `v1.13.2` | `2d84c34` | 2026-09-04 | EN: Hotfix 13.2 — App Lock made real: "require authentication to open", auto-lock timeout and hide-in-app-switcher now drive actual behaviour via `AppLockSession` (pure decision) + `AppPrivacyController` (lifecycle, gate, switcher cover) + `AppLockCoverView`. Master-password policy no longer raises the system iPhone-passcode sheet; unlocking uses the in-app password screen. Master-password creation rules are listed and validated rule by rule. Clipboard: iPhone retries `setItems` with the same `.expirationDate` / `.localOnly` options instead of `pb.string` (which wiped system expiry); Mac still writes `.string` so other apps can paste (no system expiry). In-app timer plus ⌘Q `applicationWillTerminate` (`changeCount`) clear only if still ours; force-quit and crashes cannot. Copy confirmation and Settings state the real timeout and this Mac limit in plain language; Mac clipboard-history tools are out of reach. Mac three-column drops the sidebar-hidden branch and the orphaned `MacSidebarChrome.swift` (which referenced a removed symbol and broke the iOS build) is deleted. Masked secrets no longer leak their real length: the key list used to call `keychain.read` per record just to take `secret.count`, so plaintext entered memory on every refresh and the detail row drew one dot per character. Availability now comes from a `listAccounts` attribute query (never sets `kSecReturnData`), `KeyRecordDTO.secretLength` is gone so the UI cannot obtain a length at compile time, `SecretMask` fixes the mask at 12 dots for every key, and a key with no local plaintext shows "secret not on this device" instead of dots. Tests that asserted "dot count equals real length" now assert the length is not exposed, with an 8- vs 99-character pair as the guard. Settings writes to the synced preferences no longer block the main thread (`b566522`): clipboard-local-only, clipboard-clear-seconds and reveal-policy used to `await update` then `reload`, so a slow write froze the control and the reload could bounce it back to a value that had not landed yet; all three now go through `persistSyncedPatch` (memory first, `persist` in the background) and the reveal-policy subpage no longer reloads on the way back. `persist` itself used to spawn one detached task per write with no ordering guarantee, so rapid toggling could land "off" after "on"; writes are now queued on a `SerialWriteChain` whose enqueue happens synchronously under a lock, making chain order equal call order. Test suite: `StubEntitlements` stands in for `EntitlementServing` wherever StoreKit is not the subject — the real `currentTier()` walks `Transaction.currentEntitlements`, which stalls ~60s per call on a simulator with no reachable App Store; the three cases that genuinely test snapshot-vs-StoreKit reconciliation keep the real service. 140 tests, 0 failures, 3859s → 183s. Paywall (`ccd9d6e`): the "Relay — Coming Soon" card is gone since V1 ships no relay and an unbuyable card only suggests something is missing; plan copy now states what is actually purchasable, and the three orphaned localization keys are removed. Test isolation (`ee0d01a`): the test bundle is hosted by `ApiRelay.app`, so it runs with the app's entitlements, and `keychain-access-groups` holds exactly one group — omitting `kSecAttrAccessGroup` lands in that same group. `accessGroup: nil` was therefore never isolation: `MasterPasswordService.reset()` in six setUps, the blanket enumerate-and-delete in `KeychainStoreTests.tearDown`, and `eraseAllUserData()` in `DataLifecycleTests` were deleting the user's real master password, key plaintexts, admin credentials and backup passphrase from the device, which surfaced as the lock screen rejecting a correct master password. Isolation now goes through a Service-name prefix applied at the single funnel `serviceName(for:)`; production keeps `com.apirelay.keychain` while tests use `com.apirelay.keychain.tests` via `KeychainStore.makeForTests()`, with a regression case asserting test entries stay invisible under production Service names (read-only enumeration; it never writes or deletes real entries). Lockout escape (`b378425`): "incorrect password" and "no master password stored" no longer share one message — the first is retryable, the second is a dead end. The lock screen gains a "forgot master password" exit gated by device-owner authentication, the same bar as Settings' reset and not lower; it clears the master password and lands the policy on `.biometricOrPasscode` (just proven available) and never on `.none`, which would silently drop the reveal gate too. The master password is a latch, not an encryption key, so clearing it loses no stored plaintext. Cold start and foreground re-entry now detect "policy requires master password but none is stored" and switch the screen to device-passcode recovery instead of presenting a field that can never validate; a Keychain read failure is treated as "present" so one bad read cannot open the door. 147 tests, 0 failures. Repo tidy-up (docs only): `ApiRelay_相关展览/` (94 MB of store screenshots and recordings) is now gitignored, which only makes git remember what 热修-save.md already forbade; `具体说明/` and `研发档案/` are committed for the first time, and `研发档案/` is pinned to the repo root after moving three times in one day with none of the moves ever committed; 11 stray `.DS_Store` files deleted (none were tracked); two new signpost pages `具体说明/03-分支与流程.md` (which branch we are on, how to save; copies no hashes and no ledger prose) and `具体说明/04-AI铁律清单.md` (what each of the 8 `.cursor/rules` files governs, 7 of which load on every turn); the `ApiRelay/scripts/selfcheck.sh` dead link is now marked "does not exist yet, H1 unexecuted" in all three documents that pointed at it, and 研发档案's 10-file manifest is annotated with which 7 are still unwritten. Follow-up (same hotfix line): top-level human docs renamed with `ZL` prefix — `具体说明/`→`ZL01_具体说明/`, `研发档案/`→`ZL02_研发档案/` (still pinned at repo root); new `ZL03_原始素材/` shelf with tracked `README.md` and gitignored `相关展示截图/` + `icon素材/` (user-renamed from `相关展览/` / nested `icon/`); App Icon authority remains `ApiRelay/icon/`. / 中文：热修 13.2 — App 锁落地：「打开 App 需要身份确认」「自动锁定时长」「在应用切换器中隐藏」由 `AppLockSession`（纯决策）+ `AppPrivacyController`（生命周期、门闩、切换器遮罩）+ `AppLockCoverView` 驱动真实行为；验证方式为主密码时不再弹系统「iPhone 密码」，改走应用内解锁页；主密码创建规则逐条呈现并逐条校验；剪贴板：iPhone 补写改走同一份 `setItems`，不再用 `pb.string` 冲掉系统过期与仅本机；Mac 为保粘贴仍写 `.string`（无系统过期）。App 开着按时清，⌘Q 按 `changeCount` 尽力清，强制退出/崩溃清不了；复制提示与设置用真实时长，并写明 Mac 局限与剪贴板历史工具清不掉；Mac 三栏去掉侧栏隐藏分支，删除已失去引用、且引用已删符号导致 iOS 编译失败的 `MacSidebarChrome.swift`；遮罩不再泄露真实长度：密钥列表原先对每条调 `keychain.read` 只为取 `secret.count`，每次刷新都把明文读进内存，详情页再按字符数画点，长短密钥一眼可辨。现在「本机有无该条目」由 `listAccounts` 属性查询回答（该查询不设 `kSecReturnData`），删除 `KeyRecordDTO.secretLength` 使 UI 在编译期就拿不到长度，`SecretMask` 把点数固定为 12，本机无明文时显示「本机暂无明文」而不画点；原先断言「点数等于真实长度」的单测改为断言不暴露长度，并以 8 / 99 字符两条密钥对照守住；设置页写同步偏好不再干等保存（`b566522`）：剪贴板仅本机、剪贴板清除秒数、验证方式三处原本在主线程 `await update` 再 `reload`，写入慢时开关卡住、还会被 reload 用尚未落盘的旧值弹回，现统一走 `persistSyncedPatch`（先改内存再后台 `persist`），验证方式子页返回时不再 reload、选档改为回调上层统一写入；`persist` 原先每次起独立 `Task.detached`、彼此无先后保证，连拨同一开关可能「关」后于「开」落盘，改为入队 `SerialWriteChain`（入队在锁内同步完成，链上顺序等于调用顺序）；测试侧新增 `StubEntitlements` 顶替 `EntitlementServing`——真 `currentTier()` 要遍历 `Transaction.currentEntitlements`，模拟器上连不到 App Store，每次等约 60 秒超时，凡主题不是 StoreKit 的套件一律走桩，真正考「本地快照说已买、StoreKit 说没买该听谁」的三个用例保留真服务，全量 140 个用例 0 失败、3859 秒降到 183 秒；付费墙（`ccd9d6e`）：V1 不提供中转，一张永远不可购的「即将推出」卡片只会让人以为漏了什么，删掉该卡片、套餐说明改为直述当前能买到什么，并删除随之失去引用的三个本地化 key；测试隔离（`ee0d01a`）：测试 bundle 由 `ApiRelay.app` 宿主加载、进程带的是 App 的 entitlements，而 `keychain-access-groups` 里只有一个组，省略 `kSecAttrAccessGroup` 就落到同一个组，因此 `accessGroup: nil` 从来不构成隔离——六个套件 setUp 里的 `MasterPasswordService.reset()`、`KeychainStoreTests.tearDown` 的枚举全删、`DataLifecycleTests` 的 `eraseAllUserData()`，删掉的都是用户本机真实的主密码、密钥明文、管理凭证与备份口令，表现为锁屏输入正确主密码仍提示「不正确」。改用 Service 名前缀隔离（`serviceName(for:)` 是 save/read/delete/listAccounts 的唯一出口）：生产保持 `com.apirelay.keychain`，测试统一经 `KeychainStore.makeForTests()` 走 `com.apirelay.keychain.tests`，并补回归用例断言测试条目在生产 Service 名下不可见（只读枚举，不写不删任何真实条目）；锁死出口（`b378425`）：「主密码不正确」与「本机没存主密码」不再共用一句提示，前者可重试、后者是死局；锁屏新增「忘记主密码」，门槛为设备主人验证，与设置页「重置主密码」同一道门、不得更低，通过后清主密码并把验证方式落到 `.biometricOrPasscode`（刚验证过、必定可用），MUST NOT 落到 `.none`（那会顺手废掉取明文的门闩）——主密码只是门闩不是加密密钥，清掉不影响任何已存明文；冷启动与回前台检测「策略要主密码但本机没有」，命中时标题与主按钮直接切成设备密码恢复，不再摆一个永远验不过的输入框，读 Keychain 失败按「有」处理、不因一次读不到就把门打开；全量 147 个用例 0 失败；仓库整理（纯文档、无代码改动）：`ApiRelay_相关展览/`（94 MB 商店截图与录屏）写进 `.gitignore`，`热修-save.md` 本来就禁止提交它，现在让 git 自己记住，`git status` 不再刷一屏未跟踪；`具体说明/` 与 `研发档案/` 首次入库——`研发档案/` 一天内搬过三处（`ApiRelay/` → `具体说明/` → 仓库根）且三次都没提交，现钉死在仓库根并把理由写进 `02-路径红线.md`；清掉 11 个 `.DS_Store`（均未被跟踪）；新增两页索引：`具体说明/03-分支与流程.md`（现在在哪条分支、改完说一句「按热修-save 保存并上传」，不抄 hash 也不抄台账正文）与 `具体说明/04-AI铁律清单.md`（`.cursor/rules` 8 条各管什么、其中 7 条每轮对话自动加载）；`ApiRelay/scripts/selfcheck.sh` 是三份文档都在引用的空承诺（H1 未执行、目录都还没有），三处均已标注，不再让人以为已经有自检；研发档案 10 份清单标注其中 7 份未写（含被要求「先读」的 `01-事故复盘.md`）；`重要说明/索引.md` 的 Stage1 当前路径由 `v1.13.1` 同步到 `v1.13.2`；随后顶层中文资料统一加 `ZL` 前缀并收素材：`具体说明/`→`ZL01_具体说明/`，`研发档案/`→`ZL02_研发档案/`（仍钉在仓库根），新建 `ZL03_原始素材/`（`README.md` 入库；`相关展示截图/` 与 `icon素材/` 忽略，对应你本地改过的子目录名）；图标权威钉为 `ApiRelay/icon/`，`icon素材/` 只当导出工作稿；`.gitignore` / `热修-save.md` / 导航链接已对齐。Follow-up (docs): `ZL01_具体说明/` flattened to files only `00`–`09` — warehouse/code/path maps, design+SpecKit+AI rules, development flow, branch snapshot, and `09-设计过程.md` (methods / standing designs / process trail from `plan.1` with per-milestone 过程·作用·方法·具体设计, horizontal rules between entries); dropped nested `设计过程/` folder. / 中文：随后 `ZL01_具体说明/` 收成仅文件 `00`–`09`（仓库/代码/路径、设计与规格、SpecKit、AI 铁律、开发流程、分支快照、以及从 `plan.1` 起的设计过程航迹，每条含过程·作用·方法·具体设计并以横线分隔）；去掉嵌套的 `设计过程/` 子目录。Follow-up (2026-08-27 snapshot): `ZL01` adds `10` (AI dialog log: what a conversation finished / still owes) and `11` (format rules for `10` only); `00`/`01`/`07`/`08`/`09` navigation points to them; new always-on Cursor rule `ai-dialog-log-10-11.mdc` (rules list is now 9, 8 always-on); preview `:target` CSS `zl01-markdown-preview.css` plus `.vscode/settings.json` markdown.styles; DEBUG helper `Shared/Fakes/FakeSupport.swift` (call journal + fake DTOs) is on disk but not yet in the Xcode target. User will continue later. / 中文：2026-08-27 快照 — `ZL01` 增 `10`（AI 对话记录：做到哪 / 还欠什么）与 `11`（只约束 `10` 的排版）；`00`/`01`/`07`/`08`/`09` 导航接上；新增每次加载的规则 `ai-dialog-log-10-11.mdc`（铁律现 9 条、8 条每次加载）；预览落点 CSS 与 `.vscode` 样式指向；`Shared/Fakes/FakeSupport.swift`（DEBUG 假实现记事本与样例 DTO）已落盘、尚未加入 Xcode target。文档整理未关账，后续再改。Follow-up (2026-09-04): extract reusable doc format into `ZL01` `12`; restyle `00`–`11` (TOC, `§` headings, explicit ids, back-to-toc); drop old preview CSS / `markdown.styles`; ignore `.crossnote/`; `10` closes IAP, Guideline 2.1, and ZL navigation. Remaining: mainland filing, store hotfix 1.0.1, H1, ⌘N. Dialog-navigation `tools/` not committed. / 中文：2026-09-04 — 从 `11` 抽出可推广说明页尺子成 `12`；`00`–`11` 按目录、`§` 标题、显式锚点、返回目录对齐；去掉旧预览 CSS 与 `markdown.styles`；忽略 `.crossnote/`；`10` 关账内购、Guideline 2.1、ZL 导航。仍欠备案、热修 1.0.1、H1、⌘N。对话导航 `tools/` 未入库。Follow-up 2026-09-04 upload: Mac ⌘N wired in `VaultHomeView`; `01-事故复盘` written; **H1 executed** (`selfcheck.sh`, closeout rule/command, spec-template failure section, implement Done When, KeychainStoreTests exemption comment); `10` closes ⌘N/H1/复盘. Remaining: H2–H4/99, filing, store 1.0.1, side accounts. / 中文：续传 — Mac ⌘N 已接；写就事故复盘；**H1 已执行**；`10` 关账三项。仍欠 H2–H4/99、备案、1.0.1、旁账。Follow-up 2026-09-04 H2: `AppRuntime` single env authority; Keychain/UserDefaults production touch fails in tests; `RevealPolicy.noVerification` (rawValue still `none`); `SWIFT_TREAT_WARNINGS_AS_ERRORS`. / 中文：H2 止血 — 环境判断收口；测试碰生产钥匙串/本机设置当场崩；清 RevealPolicy 撞名警告并警告当错误。Follow-up 2026-09-04 H3a: protocols gain erase/batch/startListening APIs; services + AppEnvironment take `any XxxServing`. / 中文：H3a — 协议补缺口；服务与组装根改认接口。Follow-up 2026-09-04 H3b: 13 DEBUG Fake actors under Shared/Fakes. / 中文：H3b — 配齐 DEBUG 假零件。Follow-up 2026-09-04 H3c: `AppEnvironment.makePreview` + Vault/Settings `#Preview`. / 中文：H3c — 救活 Xcode 预览。Follow-up 2026-09-04 H4: Stage1 failure exits — App Lock + biometricOnly with no biometry recovers via device passcode and downgrades to biometricOrPasscode; missing local secret is visible in list/copy/reveal (not swallowed as generic copy failure); backup export/import report `keysWithoutSecretCount`. / 中文：H4 — Stage1 失败出口：仅生物识别不可用时可用设备密码解锁并降级；本机无明文在列表/复制/查看可辨；备份导出导入报告无明文密钥数。 | 商店号仍为 **1.0.0**；不覆盖 `v1.13` / `v1.13.1`，不移动 `main` / tag；外观/默认视角/指派筛选仍写本机 `DevicePreferences`，存储归属未改 |
| `v1` | `2d84c34` | 2026-09-04 | EN: Stage1 tip advances to the v1.13.2 hotfix; release references stay frozen. / 中文：大阶段 1 tip 前进到 `v1.13.2` 热修；已发布引用保持冻结 | `main` / `release/1.0.0` 不动 |
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
