# 阶段2：Grok实施前检查报告

> **历史报告：** 只描述当时快照和检查结论，不再路由后续阶段。现行边界见 [`19-现行结论与历史材料边界.md`](./19-现行结论与历史材料边界.md)。

- 阶段：2
- 时间：2026-09-14 22:13 CST
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`（与契约 `baselineHead` 一致，未离开基线）
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：`00-总流程操作台.md`、`00A-压力测试样本.md`、`00C-任务契约.json`、`01-执行计划-初稿.md`、`02-检查计划-初稿.md`、`ZL00_项目总控/04-双AI协作与独立审计.md`、`ApiRelay/specs/playbooks/身份验证方案.md`、`ApiRelay/specs/001-key-vault/follow-ups/identity-auth/spec.md`、宪法 VIII、`001-key-vault` 的 `spec.md` / `data-model.md` / `quickstart.md` / `plan.md` / `tasks.md` / `contracts/module-interfaces.md`、P03/P06 playbook、以及身份验证相关 Swift 与测试（未读 `tools/`）
- 当前授权：只读检查；唯一允许新增本文件。未改正式规格、代码、测试；未暂存、提交、上传或切换分支
- 检查器：`python3 ZL00_项目总控/自动化/check_multi_ai_workflow.py --work-package "…/v1.13.9-身份验证四档与主密码调整"` → 退出 0；`下一阶段: 2 负责人: Grok`（检查前、写本文件之前）；`checkerGrantsExecutionAuthority` 语义为假。检查器只判断路由，不授予执行权

## 检查前状态

| 项 | 事实 |
| --- | --- |
| 仓库根 | `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github` |
| 分支 / HEAD | `v1.13.9` / `6ec5ff7c67547637bbd55f528276422395e28c03` |
| 暂存区 | 空 |
| worktree | 仅本仓库一份 |
| 保护 refs | `main` 与 `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd` |
| 未跟踪 | 本工作包目录；`tools/`（契约 `knownUntracked`，本阶段未读） |
| 前置产物 | `01`、`02` 存在；`03` 检查前不存在，未覆盖 |
| 写入冲突 | 无 |
| 能否进入阶段3 | 能。下列「阻塞」挡住的是 W1 起的代码实施，不是阶段3写最终计划。最终计划必须把未决项列为用户确认关口 |

---

## 1. 旧规格冲突清单（W0 必须消成一个答案）

拍板入口（2026-09-10）是 playbook 与 follow-up。宪法 **v2.13.0** 与 FR 正文仍是旧句；follow-up 已声明「不得再当现行」，但正文未改。

| # | 旧句仍在何处 | 定稿 | 现行代码实际 |
| --- | --- | --- | --- |
| C1 | 宪法 VIII：取出明文门闩含「不验证」；**未写**出厂默认。FR-003 / data-model / `UserPreferences` 默认 `none`；quickstart §1.2「默认档（不验证）」；`PreferencesServiceTests` 断言 `.noVerification` | 出厂 **设备验证**；不验证仍可选 | 新安装与 `fakeDefault()` 都是 `.noVerification` |
| C2 | FR-003 四档含「仅生物识别」；设置列出 `biometricOnly`；文案「仅面容 ID / 仅触控 ID」 | 四档：不验证 / 设备验证 / 应用密码 / 生物验证或应用密码。旧 `biometricOnly` **迁到设备验证** | `RevealPolicy` 仍含 `biometricOnly`；无新档 |
| C3 | 宪法 VIII、FR-006/006a/061：加密导出与永久删除 `confirmMandatory` **不可关**；P06「导出前门闩不可关闭」 | 不验证时导出直接走；永久删除只留破坏性确认。其他档按**当前验证方式**。管理类凭证仍强制设备主人 | 备份导入导出、删除/恢复/永久删除、清空、使用方删除全部走 `confirmMandatory`（忽略用户档） |
| C4 | 宪法 VIII、FR-066：降低安全一律不可关闭的**设备主人** | 降低用**当前**验证方式；persist 失败界面不降 | `SettingsView.persistSyncedPatchAsync` 降低时调用 `confirmMandatory`（设备主人） |
| C5 | 宪法 VIII、P03、`RevealGateServing` 注释：「鉴权 MUST NOT 缓存超过单次操作」 | 同一详情且未离开：查看后立刻复制不二弹；关详情 / 换密钥 / 离前台 / 自动锁后失效。不得用于导出/删除/清空 | 无授权缓存。`copySecretToClipboard` 与 `revealSecret` 各自 `runGate` |
| C6 | FR-003 / FR-021 / data-model：「`revealPolicy` 单一字段同时管辖查看与复制」；设置只有一行验证方式 | 用户三行：**验证方式 / 自动锁定 / 取用验证**。编辑、回收站、备份、删除不另开开关 | 无「取用验证」字段。查看/复制始终跟 `revealPolicy`。自动锁定已是独立子页（`appLockEnabled` + 时长） |
| C7 | 宪法 VIII：「鉴权失败 MUST 提供降级方案（设备密码），不得完全锁死」 | 「生物验证或应用密码」取消整段即结束，**不得改弹设备密码**；用户显式选应用密码 | `biometricOrPasscode` 用 `deviceOwnerAuthentication`（系统会回落设备密码）。`biometricOnly` 用 `WithBiometrics`，取消不回落设备密码——更接近新组合档，但没有「使用应用密码」入口 |
| C8 | `AppPrivacyController.promptUnlock`：`.noVerification` 且 App 锁开着 → 仍 `confirmMandatory`，「避免开关空转」；`AppLockPreferences` 注释写明此点 | 不验证时**不上锁**、无假锁屏；自动锁定/取用验证开关保留并显示「已开启，当前不生效」 | 与定稿相反：不验证 + 开锁仍弹设备主人 |
| C9 | 设置页重置主密码后，若本机已无密且仍停在 `.masterPassword`，`skipReauth` 写回 **`.noVerification`**（`SettingsView` 约 239–244 行） | 忘记密码经设备主人重置，只清本机门闩；**不得因失败改成不验证**。锁屏恢复路径已落到 `.biometricOrPasscode` | 锁屏恢复与设置重置不一致；设置路径违反定稿 |
| C10 | 契约 `module-interfaces.md` 仍写 `case none`、`confirm` 在 `.none` 时成功；Swift 已是 `noVerification = "none"` | W0 须统一枚举名与 rawValue，避免只改显示名 | 代码 rawValue 已是 `none`；合同示例未跟 |
| C11 | follow-up / playbook / ZL01/14 仍写「尚未创建的 `v1.13.9`」「不要创建 v1.13.9」 | 仓库**已经**在 `v1.13.9` 基线 `6ec5ff7c`。这是路牌过期，不是产品语义 | 不改语义；W0/W6 改路牌 |

编号不重排：W0 改 FR-003 / 003a / 006 / 006a / 021 / 036 / 060 / 061 / 066 等**正文**，并升宪法版本（现行 2.13.0）与 Sync Impact。`research.md`、`checklists/requirements.md`、`P07-Catalyst.md`、P13 内测表仍含「仅生物识别」旧句，不在 `00C.allowedModify` 里，阶段3须决定是扩清单还是只改真正权威并让这些页改成链接。

---

## 2. 旧值、默认值、迁移路径

### 2.1 持久字段（现状）

| 存储 | 字段 | 同步 | 现行默认 | 定稿 |
| --- | --- | --- | --- | --- |
| SwiftData `UserPreferences`（CloudKit） | `revealPolicy: String` | 是 | `"none"`（`RevealPolicy.noVerification`） | 新安装应为设备验证；rawValue 建议继续用已有 `"biometricOrPasscode"`，**不要**把该字符串改成新组合档 |
| 同上 | `appLockEnabled` / `autoLockSeconds` / 时长 JSON | 是 | `false` / `60` / 首次预填 | 自动锁定仍独立；出厂关锁 playbook 未改，保持现行除非用户另拍 |
| 同上 | 取用验证 | **无此字段** | 查看/复制与 `revealPolicy` 耦合 | 需要**新的同步 Bool**（名称由最终计划定）。playbook **没有**写出厂开还是关 |
| `DevicePreferences` | 外观等 | 否 | 与身份验证无关 | 应用密码材料不得放这里，也不得放 `UserPreferences` |
| Keychain `.masterpw` | PBKDF2 校验材料 | **否**（`WhenUnlockedThisDeviceOnly`） | 未设 | 继续本机、不同步 |

Swift 枚举（`DTOs.swift`）：

- `biometricOrPasscode` → LA `deviceOwnerAuthentication`（系统可回落设备密码）
- `biometricOnly` → `deviceOwnerAuthenticationWithBiometrics`
- `masterPassword` → 应用层口令；`confirm` 抛 `master_password_prompt_required`
- `noVerification = "none"`

`UserPreferencesRepository.loadOrCreate`：`RevealPolicy(rawValue:) ?? .noVerification`。未知字符串会**静默变成不验证**。与 `02`「未知值安全失败而非静默不验证」以及宪法「失败 MUST NOT 写成不验证」直接冲突。这是 W1 阻塞级缺陷。

没有现成的 `revealPolicy` 迁移函数。CloudKit 多副本按指纹折叠，无 `updatedAt`（13.5 起不物理删冲突行）。迁移必须**幂等**：每次 `loadOrCreate` 把旧值映射后写回全部副本，重复启动不得在设备验证与其它档之间抖动。

### 2.2 定稿迁移（已拍板，W1 必须显式测）

| 旧 rawValue | 迁到 | 备注 |
| --- | --- | --- |
| `biometricOnly` | 设备验证（保留/写成 `biometricOrPasscode`） | 设置页不再提供仅生物识别 |
| `masterPassword` | 应用密码（可保留 rawValue `masterPassword`） | 本机无材料时不得当不验证放行 |
| `biometricOrPasscode` | 设备验证（同一 rawValue） | **禁止**把此字符串改解释成「生物或应用密码」 |
| `none` | 不验证 | 老用户选过不验证的**保持**，不要迁到设备验证 |
| 未知 | 安全失败 | 不得 `?? .noVerification` |

新档「生物验证或应用密码」必须**新 rawValue**（例如 `biometryOrAppPassword`）。`SecurityReviewTests.testRevealPolicySingleSwitchSemantics` 断言 `allCases.count == 4`：不要把旧 `biometricOnly` 留成第五个 `CaseIterable`  case；旧值在仓库层解码映射。

`00C.externalInputs.undecidedItems` 为空，但「取用验证出厂开/关」在 playbook 正文和 `00A` 拍板列表里都没有。上一工作包 `v1.13.8-多AI协作方法实战验证` 已把它标成未决。本包契约未继承。**不得在阶段4用 `true` 填这个空。**

---

## 3. 敏感操作调用图（实际入口）

统一事实：`RevealGate.confirmMandatory` **忽略** `purpose`，一律 `deviceOwnerAuthentication`。`AuthPurpose` 目前只作标签。`confirm(.noVerification)` 直接成功。

| 操作 | UI 入口 | 业务入口 | 现行门闩 | 定稿 |
| --- | --- | --- | --- | --- |
| 新增密钥/账号 | `VaultHomeView` 添加流程 | `KeyVaultService.createKey` / `createAccount` | 仅 `sessionLocked` | 各档直接进入（已对齐） |
| 查看明文 | 详情/列表 `beginReveal` → `revealReturning` | `revealSecret` → `runGate` | 当前 `revealPolicy` | 仅当「取用验证开启且不是不验证」 |
| 复制明文 | 详情 `onCopy`、列表 `beginCopy`、⌘C | `copySecretToClipboard` → **再次** `runGate` | 同上，与查看**不复用** | 同一详情查看后立刻复制不二弹；列表/另一窗不得复用 |
| 编辑密钥或账号 | 详情 `requestEditing` 先 `revealReturning` 填草稿；`editKey` 本身无门闩 | `editKey` / `updateAccount` 无 `confirm*` | 编辑借查看门闩；借不到则可能空草稿开编 | 不验证直接进；其他档用**当前验证方式**，且**独立于取用验证**。不得只靠 `revealSecret` |
| 移入回收站 | 列表/详情删除 + 部分 `confirmationDialog` | `deleteKey` / `deleteAccount` / `ConsumerToolService.deleteTool` | `confirmMandatory` | 不验证可留普通确定；其他档当前方式 |
| 回收站恢复 | 回收站按钮，无额外破坏确认 | `restoreKey` / `restoreAccount` / `restoreTool` | `confirmMandatory` | 不验证直接恢复；其他档当前方式 |
| 永久删除（单条） | `trashInlineRow` 的「永久删除」**直接** `onPermanent`，**无** confirmationDialog | `permanentlyDelete*` 先 `confirmMandatory` | 只有设备主人，无单独破坏性确认 | **必须**破坏性确认；其他档再当前方式。不验证只留确认 |
| 永久删除（批量） | 有 confirmationDialog，再 `RecentlyDeletedBatchService` | 整批一次 `confirmMandatory` | 先确认再设备主人 | 顺序已接近定稿；把门闩换成当前方式；授权不得泄漏到下一批 |
| 备份导出/导入 | `BackupSettingsViews.performExport` 不在 UI 再弹门闩 | `SecureBackupService` 进出口 `confirmMandatory` | 不可关的设备主人 | 不验证直接走；其他档进入/生成前当前方式 |
| 备份口令设/改/复制/清 | `BackupSettingsViews` UI 先 `confirmMandatory` | `BackupPassphraseService` 本身不再门闩 | 设备主人 | playbook 未单列；建议跟备份导入导出同一套「当前方式」，不要与导出叠成两次 Face ID |
| 清除全部数据 | 设置 confirmationDialog → `eraseAllUserData` | 服务内再 `confirmMandatory` | 先破坏确认、再设备主人 | 不验证只留确认；其他档确认后当前方式。会清 `.masterpw` |
| App 锁解锁 | `AppLockCoverView` / `promptUnlock` | 按 `revealPolicy` 分支；不验证仍 `confirmMandatory` | 见 C8 | 当前方式；不验证不上锁 |
| 忘记应用密码 | 锁屏 `recoverFromLostMasterPassword`；设置 `MasterPasswordSettingsView` | 设备主人后 `reset()` | 锁屏落到设备验证；设置可能落到不验证 | 只重置本机门闩，落到安全可用档（设备验证），不删密钥明文 |
| 降低安全设置 | `persistSyncedPatchAsync` | `confirmMandatory` + `SecurityPreferenceCommit` persist-then-apply | 设备主人；降低不先改内存（13.7 已有测试） | 当前方式确认；persist 失败不降（保留） |
| 管理类凭证查看/配置 | **V1 无 Swift 实现**（`setManagementCredential` 只在合同里；源码零调用） | 无 | 无 | 始终设备主人；后台刷新不弹。V2 才有产品入口。本任务不做 V2 UI，但 W0 须保留句子，避免以后误用 `confirm(currentPolicy)` |

`purgeExpiredDeletedKeys` 在会话锁下跳过、不弹门闩（FR-070）——保留。

编辑头像浏览态 `commitAvatarIfBrowsing` 注释写明不走门闩（头像不是明文）——保留，不要误接到编辑门闩。

---

## 4. 应用密码 Keychain 边界（可保留，勿回退）

`KeychainStore`：`.masterpw` / `.backuppw` → `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，`synchronizable == false`。无 `kSecAttrAccessControl`（与同步互斥；本项目门闩在应用层）。`MasterPasswordService`：PBKDF2-HMAC-SHA256、随机盐、编码 `v1:iterations:salt:hash`、恒定时间比较、连续失败限速（3 次后指数封顶 60s）。重置只删 `.masterpw`。测试走 `KeychainStore.makeForTests()`，与 App 组隔离。

`02` 要求的隔离/限速/恒定时间**已经存在**。W2 不要重写派生，除非最终计划点名。缺的是：新组合档的显式「使用应用密码」、未设时先过设备主人再设、以及错误分类（取消 / 生物锁定 / 未设 / 口令错误 / persist 失败）不能共用一句文案。锁屏已区分「未设」与「不正确」；查看路径对未设只抛 `master_password_not_set`。

---

## 5. 同步偏好与本机材料错位

已存在的死局处理：

- 同步到 `.masterPassword` 但本机 Keychain 没有材料：`refreshMasterPasswordAvailability` 在锁屏前设置 `masterPasswordMissing`，恢复出口是设备主人，然后策略落到 `.biometricOrPasscode`。读 Keychain 失败时按「有密」处理，避免误开锁。
- `.biometricOnly` 且本机无生物识别：`biometryUnavailableForUnlock` + `recoverFromUnavailableBiometry`，同样落到设备验证。

定稿后 `biometricOnly` 会迁走，这条恢复会变成历史；**同步到应用密码档且本机未设**必须留下，并覆盖：

1. App 锁开着（已有 UI）
2. App 锁关着但取用验证/编辑/导出仍要求应用密码——今日只有 `runGate` 抛错 + 设置文案，没有与锁屏同级的恢复
3. 本机不可选纯应用密码（设置已：未设则先设密页，不改策略）；他机写来的档不得在本机静默当不验证
4. 设置重置不得再写 `.noVerification`

取用验证若出厂开启、验证方式出厂设备验证：新安装查看/复制要过设备主人，即使自动锁定关闭。这是把「默认设备验证」落到取用上的后果，不是代码 bug。若取用验证出厂关闭，则新安装只改「怎么验」，查看/复制仍不验——与旧默认「不验证」对明文取出更接近，但与「出厂更安全」的观感冲突。此点见第 10 节。

---

## 6. 13.7 不可回退不变量

来源：宪法 VIII 后半、FR-065～FR-074、follow-up「与 13.7 的边界」、`AppLockSessionTests` / `AppPrivacyControllerTests` / `SecuritySettingsPersistTests` / `WindowPrivacyReducerTests` / `ScenePresenceSignalTests` / `RevealGateCoordinatorTests`。

必须继续绿、不得借四档改掉：

1. 降低已同步安全等级：persist **成功后**才改内存锁态、启动缓存、界面；失败保持原锁（含会话仍锁）。加强可先改内存。主线程不得 `await` CloudKit save。
2. 安全偏好读取失败：保持上次已知锁态与「曾开锁」缓存；不得回落关锁或写成不验证。
3. 会话锁是业务闸：遮罩不是唯一拦截；锁住时写入口拒绝且不先弹门闩；过期回收站清扫锁下跳过。
4. 快照遮罩 ≠ 自动锁计时；同组闲置不上锁、不计时、不留白锁屏。
5. 快照/解锁层按窗独立；会话锁进程级；回到前台只揭当前操作窗。
6. 应用级生命周期通知只订一处。
7. 窗口在场用可测信号；未知 ≠ 离屏；无私有 API。
8. 系统验证同时只服务一个请求；新请求取消旧请求；真正离 App 才 cancel；验证进行中不当闲置 cancel（FR-068/072）。
9. 主密码解锁走应用内口令，不弹系统设备密码框（13.2/13.7 已测）。
10. 启动缓存只回答「上次是否开锁」，不伪造验证方式。

W4 改「不验证不上锁」时，必须改掉 `promptUnlock` 里对 `.noVerification` 的 `confirmMandatory` 特例，并更新 `AppLockPreferences` 注释，同时**不得**让 `appLockEnabled == true` 在不验证档画出假锁。测试今日把「开锁 + 不验证」当成仍要设备主人；W4 要改测试口径，不是删生命周期用例。

---

## 7. 测试与人工验证能力

### 能用单测挡住的

- 默认值、rawValue 映射、未知值失败、幂等迁移：`Phase02_Data`（`PreferencesServiceTests`、`SwiftDataRepositoryTests`）今日**把默认和不验证写死**，W1 必改。
- `RevealGate` 四档矩阵、取消/失败分类：现有 `RevealGateTests` 只有 none / biometricOnly 无生物 / 主密码未设。缺：组合档不回落设备密码、设备验证政策、授权复用（应放可测纯对象，不要在 actor 里用非结构化超时 Task）。
- 降低安全 persist-then-apply：`SecuritySettingsPersistTests`、`SecurityPolicyChangeTests`（现行 rank：不验证 0、设备主人档 1、仅生物与主密码 2）。新四档 + 取用验证开关必须重写 `weakens`。
- App 锁生命周期：上节测试文件，覆盖面足够当回归网。
- 主密码 PBKDF2/限速/重置：`MasterPasswordServiceTests`、`SecurityReviewTests.testMasterPasswordNotSynchronizable`。
- 回收站批量一次门闩、锁下不先弹：`RecentlyDeletedBatchTests`、`ConsumerToolSessionLockTests`。
- 备份导出仍走门闩：`SecureBackupTests` / `DataLifecycleTests` 会随 C3 改期望。

### 单测假装不了、必须手测

- 真实 `LAContext` 弹窗、取消、生物锁定、系统回落设备密码。
- 「生物或应用密码」界面上的「使用应用密码」与取消不改弹设备密码。
- iPhone / iPad / Mac 三端：自动锁、多窗遮罩、台前同组、Mac 不自动弹系统框（已有单测辅助，仍要手测）。
- CloudKit：设备 A 改成应用密码档，设备 B 未设材料时的恢复，而不是本机内存模拟。
- 同一详情查看后复制不二弹，以及关详情/换密钥/进后台后必须再验。
- 不验证时设置后两行「已开启，当前不生效」且不置灰。

构建：共享 scheme `ApiRelay.xcscheme`。agent 构建必须独立 DerivedData，iOS 模拟器必须本地签名（仓库规则）。本阶段未跑测试或构建（只读、且未获实施授权）。

本地化：`Localizable.xcstrings` 源语言 en，可见 zh-Hans。验证方式文案仍是「面容/触控 ID 或设备密码」「仅面容 ID」「主密码」「不验证」。W5 要按设备硬件动态显示设备验证名称（FR-003a 官方译名仍有效），并补暂停提示、推荐标记、组合档。辅助功能：设置行 ⓘ 规则属宪法，不要在本任务里改行序。

`VaultHomeView.swift` 4442 行、`SettingsView.swift` 1420 行、`Localizable.xcstrings` 9808 行、`AppPrivacyController.swift` 812 行——已超过 400 行。阶段4改到哪份就在实施报告点名，**不要**顺手拆文件。

---

## 8. 精确候选文件清单（相对 `00C` 的补丁）

`00C.allowedModify` 作为**上限草稿**不够。阶段3写入 `04` 时应视为「可改集合」，并补上下列否则阶段8检查器会在白名单上失败，或执行者改到契约外。

### 8.1 已在契约、W0–W6 确实会碰到

宪法、`spec.md`、`data-model.md`、`quickstart.md`、`plan.md`、`tasks.md`、`module-interfaces.md`、follow-up、`身份验证方案.md`、P03、P06、`DTOs.swift`、`UserPreferences.swift`、`UserPreferencesRepository.swift`、`RevealGate.swift`、`RevealGateServing.swift`、`KeyVaultService.swift`、`MasterPasswordService.swift`、`PreferencesService.swift`、`SecureBackupService.swift`、`AppPrivacyController.swift`、`SettingsView.swift`、`DurationSettingsViews.swift`、`BackupSettingsViews.swift`、`AppLockCoverView.swift`、`KeyDetailView.swift`、`VaultHomeView.swift`、`VaultHomeViewModel.swift`、`Localizable.xcstrings`、`DebugSupport/Fakes`、测试目录 Phase02/03/06/08、ZL01 的 `04`/`10`/`13`/`14`、ZL02 阶段总览、`BRANCHES.md`。`DevicePreferences.swift` 预计只读不改。

### 8.2 契约未列、按调用图必须列入

| 路径 | 原因 |
| --- | --- |
| `ApiRelay/ApiRelay/Business/System/SessionLockQuerying.swift` | `SecurityPolicyChange` / `SecurityPreferenceCommit` 的 weaken 与 persist-then-apply |
| `ApiRelay/ApiRelay/Business/System/AppLockSession.swift` | 默认 `revealPolicy`、不验证仍锁的注释与冷启动行为 |
| `ApiRelay/ApiRelay/Business/System/DataLifecycleService.swift` | 清空门闩 |
| `ApiRelay/ApiRelay/Business/Vault/RecentlyDeletedBatchService.swift` | 批量一次门闩 |
| `ApiRelay/ApiRelay/Business/Vault/ConsumerToolService.swift` | 使用方删除/恢复/永久删除 |
| `ApiRelay/ApiRelay/Business/Vault/KeyVaultServing.swift` | `runGate` / `confirmMandatory` 注释与签名 |
| `ApiRelay/ApiRelay/Shared/ApiRelayError.swift` | 若要区分生物锁定/取消/未设密（尽量复用已有 case） |
| `ApiRelay/ApiRelay/ContentView.swift` | 锁屏封面参数（缺密/生物不可用） |
| `ApiRelay/ApiRelayTests/V1/Phase07_Catalyst/CatalystAdaptationTests.swift` | 仍测 `biometricOnly`；不在已列测试目录 |
| `ApiRelay/specs/001-key-vault/research.md` | 旧四档表；W0 若只改 spec 会留第二答案 |
| `ApiRelay/specs/playbooks/v1-key-vault/phases/P07-Catalyst.md` | 「无 Touch ID 则禁用 biometricOnly」 |
| `ApiRelay/specs/playbooks/v1-key-vault/phases/P13-人工操作指南/06-TestFlight内测.md` | 已提到 13.9 取用验证，W6 才改状态 |

### 8.3 默认不要改

`KeychainStore.swift` / `KeychainStoring.swift`（masterpw 策略已正确）、`ROADMAP.md`、Xcode 工程、ZL00、`tools/`、V2 Provider/用量、管理凭证 UI。合同里的 `ProviderKeyServing.setManagementCredential` 只改注释/门闩要求，不实现 V2。

`00C.allowedAdd` 里的 `阶段4A`/`阶段4B` 提示词**已经存在**，阶段4不要再建一份。

---

## 9. W0–W6 顺序：会漏入口吗？循环依赖吗？

建议保持 `01` 的 W0→W6，作如下收紧（不改已拍板语义）：

1. **W0 必须先于任何 Swift。** 否则执行者会按宪法「不得缓存」「导出门闩不可关」「失败回落设备密码」把新代码写成旧产品。
2. **W1 在用户确认取用验证出厂值之前不能写死默认。** 否则 W4 三行无法落地，W3 查看/复制会继续错误耦合。这是顺序上的真阻塞，不是循环：先阶段3让用户批，再 W1。
3. **W1 迁移必须能识别旧 rawValue；W2 不要依赖 `biometricOnly` 仍是 enum case。** 否则 W2 删 case 后未迁数据会掉进未知值分支。把映射放在仓库层，引擎只认新四档。
4. **W2 保留 `confirmMandatory` = 始终设备主人**，供管理类凭证、忘记密码、以及「组合档未设应用密码时的设密门槛」。不要把 `confirmMandatory` 改成「当前档」，否则锁屏恢复和管理类凭证会被带偏。W3 把**操作**从 `confirmMandatory` 改到「按档 `confirm`」。
5. **W3 不要做取用复用。** 查看与复制继续各验一次，直到 W5。否则 W3 测试会和 W5 抢同一行为。编辑必须新增独立 `confirm(currentPolicy)`，停止把 `revealSecret` 当编辑门闩——否则取用验证关闭时编辑会被一起放行。
6. **W4 依赖 W1 字段 + W2 引擎。** 不验证不上锁、三行暂停文案、降低用当前方式，都在这一波改 `SettingsView` 与 `AppPrivacyController`。若 W4 先于 W3，删除类仍是设备主人（更严，可接受）；反过来 W3 先于 W4，不验证用户会先看到「删除不再验身份」而 App 锁还在用旧特例——窗口期不安全。故 **W4 应紧挨 W3 之后、且同一批准计划内连续做完**，不要隔夜只合并 W3。
7. **W5 依赖 W4 的离前台/自动锁信号** 来清授权，不要第二套计时。复用范围只限同一 `KeyDetailView` 实例与同一 `keyId`；列表 `beginCopy`、⌘C、另一窗口不得读该授权。
8. **W6 最后。** 含改测试期望、三端手测、敏感信息扫描、ZL01 路牌。`14` 现在仍指向 13.8 方法包和「不要创建 13.9」，W6 才按事实改，避免阶段2/4 手写易过期阶段号。

未发现「A 需要 B 的成品、B 又需要 A 的成品」这种循环。唯一类似循环的是 **取用验证默认值 ↔ W1 模型**，用用户批准解开，不用调换波次。

漏入口风险：使用方删除、备份口令复制、单条永久删除无破坏确认、设置重置落到不验证、Phase07 测试、列表复制与详情复用边界。上表已列出。

---

## 10. 建议（给阶段3，不改变拍板）

- 设备验证继续持久化为 `biometricOrPasscode`；应用密码继续 `masterPassword`；组合档全新 rawValue。显示名与本地化另改。
- 未知 `revealPolicy`：加载时 fail-closed（按设备验证挡操作 + 保持锁态），并给恢复；**禁止**回落不验证。具体 UI 文案由最终计划写，不必新开产品方向。
- `SecurityPolicyChange.rank`：不验证最弱；关掉取用验证或自动锁定算降低。三档有验证方式之间是否两两算「降低」playbook 没写全——见用户决定。在未确认前，最终计划应给出一张显式表，不要让执行者猜。
- V1 不实现管理凭证 UI；W0 把合同「MUST `confirmMandatory`」写清楚；W3 不把该协议改成当前档。
- 单条永久删除补破坏性确认，排在身份验证之前（与批量、清空一致）。
- 设置「重置应用密码」与锁屏恢复合并为同一落点（设备验证），删掉写 `.noVerification` 的分支。

---

## 11. 需要用户决定（阶段3写入最终计划，批准前不定稿受影响默认）

1. **取用验证出厂开还是关。** 拍板正文没写。契约 `undecidedItems` 却是 `[]`。旧代码等价于「跟着验证方式走」（没有独立开关）。若开：新用户默认设备验证 ⇒ 查看/复制也要验。若关：新用户只在开了自动锁定（或其它仍跟验证方式的操作）时才验，查看/复制仍直接做。
2. **三档有验证方式之间，怎样算「降低安全」。** 例如设备验证 → 应用密码、设备验证 → 生物或应用密码、应用密码 → 设备验证。现行 rank 把主密码当作比 `biometricOrPasscode` **更强**（所以改成主密码不重验，改回去要验）。
3. **是否把 `research.md` / P07 / P13 内测 / requirements 清单列入 W0 允许修改。** 不列入则那些页会继续以旧四档自称现行；列入则扩大 `00C`。不涉及新安全默认，但是否扩范围要用户点头。

以下**不是**新决定，最终计划按已拍板写即可：出厂验证方式=设备验证；不验证仍可选；管理类凭证始终设备主人；复用不另做秒数；13.7 生命周期不回退；不做 V2/可用性检测/改 main 或 tag。

---

## 12. 阶段3应吸收的阻塞（实施前必须在最终计划里有答案）

- B1 取用验证出厂值未拍板（用户）。
- B2 未知持久值今日静默变不验证（计划必须改仓库，不要留给执行者发挥）。
- B3 `00C` 文件白名单缺 SessionLock/AppLockSession/DataLifecycle/回收站批量/使用方/Phase07 等（计划必须扩，否则改了检查器也会红）。
- B4 设置重置应用密码写回不验证（按已拍板修，不要再问要不要保留）。
- B5 单条永久删除缺少破坏性确认（按已拍板补）。

无证据表明需要在阶段2停止、改走「通用-只检查当前阶段」。身份、HEAD、单一写入者、空暂存均匹配。

---

## 方法观察

上一包已把「取用验证出厂开关」标成未决，本包 `00C.undecidedItems` 写成空数组，造成阶段2必须重新发现同一缺口。这是工作包之间未继承未决项，不是漏触发或多 AI 误唤醒。ZL01/14 与 playbook 仍写「不要创建 / 尚未创建 v1.13.9」，而 Git 已在该分支——状态页漂移，留给 W6，不在本阶段改。未发现需要另开方法整改包的问题。

写入状态：已停止
