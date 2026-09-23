写入状态：未停止

# 阶段4：Grok波次整改报告（U2-W3 / U2-R1）

- 阶段：4
- 修订ID：U2
- 计划修订：U2-R1
- 波次：U2-W3（只修 W3/06 B04；不重做 W0/W2 或已修 B01–B03）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2-R1 版 `04` 第八节第五小节、`05` 第十二节 F、`00C`、W3/05、W3/06、当前生产接缝源码
- 批准原文：2026-09-15 用户「明确同意 U2-R1 的 04 和 05」并执行 `提示词/阶段4-Grok执行下一波.md`
- 批准版本：本工作包当前磁盘上的 `04-最终执行计划.md` / `05-最终检查计划.md`（文首计划修订 `U2-R1`）
- 实际授权：只做 U2-W3 本次 B04 提交接缝整改；配对为 W3/08。不进 U2-W5；不覆盖 W3/01–06；不处理 `tools/`、xcodeproj、暂存、提交、上传、main/tag
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` 对象 = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree；`git diff --check` 通过

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2-W0/08、U2-W2/10 通过。U2-W3 最新偶数报告是 W3/06，结论不通过（计划修订 / B04）。本文件为 `实施波次/W3/` 下一个连续奇数报告 `07`，不覆盖 01–06。
- 上一写入者：W3/06 已停止。W0/07 旧 U2 批准不够；本波记录的是 U2-R1 批准原文。
- 未读取、未修改 `tools/`。未改 Vault/备份普通入口（属 U2-W5）。未改 PBKDF2、Keychain 服务、可访问性或限速。未改同步模型。

## 2. 本波实际文件（均在 U2-R1/原 U2-W3 清单 ∩ `00C.allowedModify` 内）

| 文件 | 做什么 |
| --- | --- |
| `Business/System/SessionLockQuerying.swift` | 请求 ID 在 `begin` 时递增；存储 `sceneActive`；`authorize` 与 `invalidate` 争同一把 `NSLock`；`AppPasswordSubmitContext` |
| `Business/Vault/RevealGateServing.swift` | 创建/保留/恢复协调器每个 await 之后再授权；`awaitPersist` 把许可和打开时策略传入队列 |
| `App/AppEnvironment.swift` | 创建/保留/恢复生产入口必带 `request`；材料写入与策略 persist 走许可；DEBUG 便捷重载只给测试，仍创建真实 lease |
| `Business/System/MasterPasswordService.swift` | `setPassword`/`reset(expectedRevision:)` 在排他提交里、Keychain 写入/删除前再授权；1 参走协议扩展 |
| `Business/System/PreferencesService.swift` | 协议持久化接缝：出队授权 → 核对当前策略 → 写入前再授权；入队不等于已提交 |
| `UI/Settings/SettingsView.swift` | 创建/保留/重置把同一 lease+token 交给环境；确认不再写死 `sceneActive: true`；离前台 `noteSceneActive` 并作废 |
| `App/AppPrivacyController.swift` | 锁屏恢复自有 lease；离屏作废；打开策略从落盘快照，不盲信未 `start` 的内存会话 |
| `DebugSupport/Fakes/FakeMasterPassword.swift` | 2 参写入/条件删除；忙碌等待注入钩子 |
| `DebugSupport/Fakes/FakePreferences.swift` | 许可 persist、延迟注入、写入计数 |
| `Phase03_Vault/RevealGateTests.swift` | F 矩阵：协调器反例、生产环境创建/恢复、线性化、旧 `end` 不得清新请求 |
| `Phase06_Settings/PreferencesServiceTests.swift` | 真实 `SerialWriteChain`：排队失效不覆盖；另窗已改策略拒绝过期写入 |
| `Phase06_Settings/SecuritySettingsPersistTests.swift` | 保留密码切档确认与生产 `request` 对齐 |
| `Phase06_Settings/AppPrivacyControllerTests.swift` | 锁屏恢复设备主人返回前离屏：不 persist、不删材料、保持锁定 |

未改但属允许清单：`AppLockSession.swift`、`ContentView.swift`、`DurationSettingsViews.swift`、`AppLockCoverView.swift`、`Localizable.xcstrings`、`FakeRevealGate.swift`（沿用已有 `confirmMandatoryHook`）。未新增生产/测试文件。

## 3. 提交定义（针对 W3/06 原码反例）

W3/06 反例：设备主人闭包里 `invalidate` 后，协调器仍 `setPassword` + persist。现顺序为：

1. 当前确认前后 `authorize(.proceed)`。
2. 设备主人 await 返回后再 `authorize(.proceed)`；失败则材料写入次数为 0、策略写入次数为 0。
3. `setPassword(..., authorizing:)` 在排他区、`keychain.save` 之前再 `authorize(.materialWrite)`。许可已取得后的 Keychain I/O 视为该步已开始，不回滚。
4. 策略 `persist`：入队不是提交。出队后授权；若带 `expectedCurrentPolicy` 则 `load` 核对打开时策略，写入前再授权。失效或另窗已改档则拒绝，不覆盖新策略。
5. 恢复：设备主人后授权 → 设备档 persist 授权 → `reset(expectedRevision:authorizing:)` 删除前再授权。策略已落到设备档而删除被拒：保留材料、保持锁定。
6. `NSLock` 不跨 await。线性化点是 lease 上 `authorize`/`invalidate` 的同一把锁。
7. 取消系统验证或抑制成功弹窗不是提交保护；`finishPageRequest` 仍用 `isFresh` 抑制过期成功弹窗，作为附加层。

## 4. 05 第十二节 F 矩阵 → 测试名

两种目标 `.masterPassword` / `.biometryOrAppPassword` 均在对应测试的 `for` 循环里执行。

| 注入时点 | 测试 | 观察 |
| --- | --- | --- |
| 当前确认等待中取消 | `testCreateStopsWhenRequestInvalidatedDuringCurrentConfirm` | 设备确认不开始；写/persist=0；材料 unset |
| 设备主人成功后、材料许可前失效 | `testCreateStopsAfterDeviceOwnerBeforeMaterialWrite`；`testEnvironmentCreateStopsAfterDeviceOwnerIfRequestInvalidated` | W3/06 反例现为 0 写 / 0 persist |
| 材料忙碌等待期间取消 | `testMaterialWriteRefusesWhenInvalidatedDuringBusyWait` | 无新许可不得写；旧策略保留 |
| 材料已写、策略许可前失效 | `testMaterialKeptWhenPolicyPersistInvalidated` | 材料 set、目标未保存、不盲删 |
| 策略已排队尚未实际写入 | `testQueuedPolicyPersistRefusesAfterInvalidateWithoutCoveringNewPolicy` | 真实队列拒绝过期写入；占位写入仍落盘但不改验证档 |
| 另窗已改当前策略 | `testQueuedPersistRejectsWhenOpenedPolicyAlreadyChanged` | 不覆盖新策略；页面 token 仍可另论 |
| 许可与失效竞争 | `testAuthorizeInvalidateLinearizationHasSingleWinner` | 同一把锁单赢家；事后该 token 不能再授权 |
| 策略已提交后失效 | `testCommittedPolicyNotRevertedByLaterInvalidation`；`testCommittedKeepExistingRemainsAfterLaterInvalidation` | 不倒转已落盘档 |
| 恢复：设备确认后、设备档许可前 | `testRecoveryStopsBeforeDevicePolicyPersist`；`testForgotMasterPasswordBackgroundDuringDeviceOwnerDoesNotPersistOrDelete` | 不保存设备档、不删材料、保持锁定 |
| 恢复：设备档已保存、删除许可前 | `testRecoveryStopsBeforeDeleteAfterDevicePolicySaved` | 材料仍 set；策略已是设备验证；不落到不验证 |
| 旧 defer / 再进入 | `testOldEndDoesNotClearNewerRequest` | 新 token ≠ 旧 token；旧 `end` 不清新忙碌 |

B01–B03 接线未重做实现；本波回归仍跑：`SecuritySettingsPersistTests` 保留密码切档、`AppPrivacyControllerTests` 恢复锁态/不落到不验证、`RevealGateTests` 既有创建/恢复部分失败。

## 5. 测试与自检

iPhone 17 Pro / iOS 26.5 模拟器，`-derivedDataPath /tmp/ApiRelayAgentDD`，本地签名：

```text
/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_17-34-28-+0800.xcresult
Selected tests: 186 passed, 0 failed
RevealGateTests / PreferencesServiceTests / SecuritySettingsPersistTests /
AppPrivacyControllerTests / MasterPasswordServiceTests / SecurityReviewTests /
SecurityPolicyChangeTests / RevealGateCoordinatorTests
```

```text
/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_17-36-13-+0800.xcresult
AppLockSessionTests: 29 passed, 0 failed
```

Mac Catalyst 本波因工程 entitlements 需要开发证书，未作为测试目的地；不是产品失败。

`bash ApiRelay/scripts/selfcheck.sh`：红线 1 通过，退出码 0。报告 1 中本波触及的过大文件：`SettingsView.swift` 1989 行、`AppPrivacyController.swift` 955 行、`SessionLockQuerying.swift` 530 行、`AppEnvironment.swift` 400 行。未拆文件。

## 6. 实现收尾四问

1. **外部资源**：材料写入仍只走 `.masterpw` Keychain（生产 `MasterPasswordService`；测试 `KeychainStore.makeForTests()` 或 `FakeMasterPassword` 内存）。策略写入走 SwiftData `PreferencesService`（本波队列测试用 `AppSchema.makeInMemoryContainer()`）或 `FakePreferences` 内存箱。未新增 CloudKit / UserDefaults / App Group。`AppLockLaunchCache` 仅武装缓存，相关测试 `resetForTests()`。
2. **失败路径**：过期请求抛 `stale_page_request`，设置页走既有失败提示；材料已写而策略未切仍用部分成功文案。恢复失败保持锁定，用户用当前落盘档再解。前提：页面/锁屏必须传入同一 `request`；DEBUG 无 `request` 的测试重载会另开临时 lease，RELEASE 设置页与锁屏恢复走必填 `request`。
3. **接缝**：`FakeMasterPassword` / `FakePreferences` / `FakeRevealGate` 可注入授权失败窗口。`PreferencesServing` 生产队列由 `PreferencesServiceTests` 直测，不靠 UI。
4. **文件粒度**：见上，超过 400 行的已点名，未擅自拆。

## 7. 三端接线（本波不冒充运行通过）

| 端 | 共用逻辑入口 | 本波结果 | 未验证 |
| --- | --- | --- | --- |
| iPhone | `MasterPasswordSettingsView` 创建/保留/重置；`AppPrivacyController.recoverFromLostMasterPassword` | 模拟器共享测试 186+29 绿；未做真机系统弹窗/手测 | 真机 Face ID、后台、多窗 |
| iPad | 同一 SwiftUI 设置页与锁屏恢复 | 未跑 iPad 模拟器/真机 | 分栏、台前、系统验证 |
| Mac Catalyst | 同一源码；离屏作废走 `handleDidEnterBackground` / `handleHostFocusDidChange` | 本波未跑 Catalyst 测试（签名） | 多窗、触控 ID 盖在别的软件上 |

U2-W6 仍承担三端人工矩阵。本波共享单元测试不能代替逐端导航。

## 8. 未验证 / 停止点

- 普通入口去掉延迟设密：U2-W5。
- iPhone/iPad/Mac 手测、双设备 CloudKit、旧 W6/02 阻塞、工程 manifest：U2-W6。
- 未改 `04`/`05` 正文状态行（仍可能写「待批准」）；实施授权以本报告批准原文为准，不回写计划。
- W2 限速/只创建/条件删除：本波跑了 `MasterPasswordServiceTests` 与 `SecurityReviewTests`；W3/08 仍须按 04 重验受影响 W2 接缝。

## 9. 方法观察

06 的计划失败已被 U2-R1 覆盖，本波未因它退回阶段 3。保护是「尚未取得许可的步骤拒绝」，不是回滚已获许可并开始的 Keychain 写入。若 4A 发现 RELEASE 生产入口仍能调用无 `request` 重载，或队列核对打开策略的时机仍有窗口，视为本波未完成而非新开 W5。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
