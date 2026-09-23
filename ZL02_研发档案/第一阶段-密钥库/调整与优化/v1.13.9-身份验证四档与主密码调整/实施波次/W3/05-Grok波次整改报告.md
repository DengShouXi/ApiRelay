# 阶段4：Grok波次整改报告（U2-W3）

写入状态：未停止

- 阶段：4
- 修订ID：U2
- 波次：U2-W3（整改 W3/04 B01–B04）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2 版 `04` 第八节、`05` 第十二节、`00C`、W3/03、W3/04-Codex波次复验报告、当前设置/锁屏源码
- 引用阻塞：W3/04 B01 已有密码切档缺当前验证；B02 设置页缺材料无独立恢复；B03 锁屏恢复仍自动解锁并吞部分失败；B04 页面待办无生命周期/同步失效
- 批准来源：W0/07 记录 2026-09-15 用户原文「同意 U2 执行计划和检查计划」。本波未要求重复批准。
- 实际授权：用户调用阶段4；W3/04 普通整改失败，只修本波 B01–B04；不进 U2-W5；不覆盖 W3/01–04；不处理 `tools/`、xcodeproj、暂存、提交、上传。
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2-W0/08、U2-W2/10 通过。U2-W3 最新偶数报告是 W3/04，结论不通过（普通整改）。本文件为 `实施波次/W3/` 下一个连续奇数报告 `05`，不覆盖 01–04。
- 上一写入者：W3/04 已停止。未读取、未修改 `tools/`。未改 Vault/备份普通入口（属 U2-W5）。未改 `AppEnvironment.swift`（属 U2-W2 额外文件）。

## 2. 针对 B01–B04 的实际修改（均在 U2-W3 允许清单 ∩ `00C` 内）

| 文件 | 做什么 |
| --- | --- |
| `SessionLockQuerying.swift` | 新增 `AppPasswordPageSurface`（创建/当前方式确认/改密/恢复分开建模）、`AppPasswordSettingsFlow.confirmCurrent`（生产可调用认证接缝）、`AppPasswordPageLease`（请求代际、防重入、当前策略新鲜度）。 |
| `SettingsView.swift` | 已设切档显示当前应用密码输入或组合档「纯生物 / 使用应用密码」；已设非当前档可改密；unset/unreadable/set 均有独立恢复；加载中不冒充未设；离开前台/返回/当前策略变化作废旧请求并取消系统验证；`reset` 有 `isSaving`/lease 防重入。 |
| `AppPrivacyController.swift` | `recoverFromLostMasterPassword` 成功或部分成功都不再 `finishUnlockSucceeded`。只把已落盘策略同步进会话、清旧待办、保持锁态。`stale_concurrent` 保留 `unlockError`。 |
| `FakeRevealGate.swift` | 增加 `setAfterConfirmHook`，供确认过程中使页面请求失效。 |
| `Localizable.xcstrings` | `settings.appPassword.recover`、`settings.appPassword.requestExpired`。 |
| `SecurityPolicyChangeTests.swift` | 两目标×当前四档×材料三态共 24 格表面；当前应用密码空口令拒绝；组合档纯生物/显式口令/空口令不降设备主人；lease 重入与失效。 |
| `SecuritySettingsPersistTests.swift` | 已设保留密码继续的真实 persist 正反例；确认中失效不落盘；落盘后失效不倒转；unset 设置恢复落到设备验证。 |
| `AppPrivacyControllerTests.swift` | 恢复成功仍锁；缺材料恢复仍锁；过期删除保留错误提示与锁态。旧「恢复后自动解锁」断言已改。 |

本波未改：`AppEnvironment.swift`、`RevealGateServing.swift`、Vault/备份、`ContentView.swift`、`DurationSettingsViews.swift`、`AppLockCoverView.swift`。未新增生产或测试文件。未改 `ZL01/14`。

## 3. 生产调用链（关闭的缺口）

1. **B01 已设切档：** `AppPasswordPageSurface.showsCurrentMasterPasswordField` / `showsComboExplicitPasswordField` 与「是否改新密码」无关。保留现有走 `persistPasswordDependentPolicyKeepingMaterial` → `AppPasswordSettingsFlow.confirmCurrent`。当前应用密码空口令抛 `master_password_prompt_required`，不 persist。当前组合档默认纯生物；显式「使用应用密码」走 `confirmCombinationWithAppPassword`，空口令抛 `combination_password_empty`，不改走设备主人。
2. **B02 独立恢复：** 材料 unset / unreadable / set 在设置页都显示恢复。走既有 `resetAppPasswordAndFallToDeviceAuth`（设备主人 → 安全 persist 设备档 → 条件删除）。锁屏缺材料仍走 `recoverFromLostMasterPassword`，不要求不存在的旧密码。
3. **B03 锁屏恢复：** 成功只 `applyRecoveryOutcomeKeepingLock()`。用户需用新的设备验证再 `requestUnlock()`。部分成功（策略已是设备验证、材料删除过期）保留 `unlockError` 与锁态。
4. **B04 待办失效：** `AppPasswordPageLease` 绑定目标与打开时的当前策略。重复点击 `begin()` 返回 nil。返回/离前台/当前策略被同步改成非本页目标时 `invalidate` + `cancelCurrentAuthentication`。`confirmCurrentIfNeeded` 在确认前后 `requireFreshForConfirm`。已经 persist 的结果不倒转；页面失效后不弹成功。

## 4. 测试证据

iPhone 17 Pro 模拟器，iOS 26.5，DerivedData `/tmp/ApiRelayAgentDD`，签名保留：

```text
AppLockSessionTests 29
AppPrivacyControllerTests 42
RevealGateCoordinatorTests 13
ScenePresenceSignalTests 3
WindowPrivacyReducerTests 4
SecurityPolicyChangeTests 18
SecuritySettingsPersistTests 12
MasterPasswordServiceTests 15
RevealGateTests 52
CatalystAdaptationTests 4
合计 192 passed / 0 failed
xcresult: /tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_16-55-16-+0800.xcresult
```

本波要点（不是只测 destination 纯函数，也不是旧自动解锁绿）：

- `testAppPasswordPageSurfaceMatrixForBothTargets`（24 格）
- `testSettingsConfirmRequiresCurrentMasterPasswordWhenSet`
- `testSettingsConfirmComboCanUseBiometryOrExplicitAppPassword`
- `testKeepExistingMasterToComboRequiresCurrentPasswordAndDoesNotPersist`
- `testKeepExistingMasterToComboPersistsTargetWithoutSetPassword`
- `testKeepExistingComboToMasterUsesBiometryOrExplicitAppPassword`
- `testKeepExistingInvalidatedDuringConfirmDoesNotPersist`
- `testCommittedKeepExistingRemainsAfterLaterInvalidation`
- `testSettingsRecoveryFromUnsetMasterFallsToDeviceAuth`
- `testForgotMasterPasswordUnlocksAfterDeviceOwnerAuth`（断言已改为仍锁）
- `testRecoveryClearsMissingFlag`（仍锁）
- `testLockRecoveryDoesNotDeleteNewerMaterial`（仍锁且保留错误）

`git diff --check` 对本波文件通过。

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
```

未重跑全量工程测试。本波模拟器结果不是平板/电脑运行证据，也不是真实系统弹窗手测。

## 5. 收尾四问

1. **外部资源：** 应用密码材料仍只在本机 `.masterpw`。切档 persist 测试用 `FakeMasterPassword` + `FakePreferences`（`AppEnvironment.makePreview()`），不碰真实 Keychain / CloudKit。锁屏恢复回归：缺材料/成功路径用 `KeychainStore.makeForTests()` + 内存 `PreferencesService`；过期删除用 `FakeMasterPassword` + `FakePreferences`。`AppLockLaunchCache` 仍按测试 `setUp` 重置。未打开 `xcodecloud/manifest.json`。
2. **失败路径：** 已设切档不输入当前应用密码：提示需要当前密码，策略不变。组合档显式口令为空：拒绝且不降设备主人。页面离开/策略变化：旧确认不能再 persist，文案「此操作已失效」。恢复取消：策略与材料不变。恢复 persist 失败：锁态与材料保留。恢复删除过期：设备档若已保存则如实保留错误，不自动解锁、不删别人刚写入的材料。恢复成功：落到设备验证、丢弃原待办、**仍锁着**，用户自行按新档解锁。不承诺取消能倒转已经落盘的事务。
3. **接缝：** `AppPasswordPageSurface` / `AppPasswordSettingsFlow` / `AppPasswordPageLease` 可在测试里直接调用，不经 SwiftUI。`RevealGateServing` / `MasterPasswordServing` 仍有 Fake。页面确认过程用 `FakeRevealGate.setAfterConfirmHook` 注入失效。未新增 protocol。
4. **文件粒度：** `SettingsView.swift` 现 1991 行，已超过 400。本波只改应用密码页状态机，不拆文件。`AppPrivacyController.swift` 899 行、`SessionLockQuerying.swift` 472 行，同样超限，未拆。

## 6. 未验证 / 停止点

- 普通入口去掉延迟设密（Vault/备份/取用）：U2-W5。
- iPhone/iPad/Mac 选档、系统弹窗、分栏/多窗手测、双设备、旧验收阻塞、工程 manifest：U2-W6。
- 本波未在电脑或平板跑过界面。共用状态机已接三端同一 `MasterPasswordSettingsView` / `recoverFromLostMasterPassword`，不能冒充三端运行通过。
- 创建设密流程中，设备主人验证与 `setPassword` 仍在 `AppEnvironment.createAppPasswordMaterialThenPersist` 内部；本波未改该文件。离开时取消系统验证可打断进行中的 `confirmMandatory`；若设备主人已成功返回、写入已经开始，按 B04 不倒转已落盘事务。

## 7. 方法观察

W3/04 指出测试数量真实不等于产品语义正确。本轮把「恢复后必须解锁」改成 U2 锁态断言，并为切档确认补了可调用生产接缝，而不是再加一条 destination 纯函数。若下次审计仍只看绿数、不看断言是否还在描述旧行为，还会把自动解锁当成通过。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
