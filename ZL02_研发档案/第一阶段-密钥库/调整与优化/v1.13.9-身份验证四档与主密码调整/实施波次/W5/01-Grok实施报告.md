# 阶段4：Grok实施报告（W5）

写入状态：未停止

- 阶段：4
- 波次：W5（同详情取用复用、组合档界面与本地化）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：经用户批准的 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W4/10-Codex波次复验报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W0–W4 已通过；W4/10 写明可进入下一波。`04`/`05` 文首仍留有 W4 修订「等待批准」字样；该修订已用于关闭 W4，本次按阶段4「最早未通过波次」只实施 W5，未改 `04`/`05`，未一次做完全部后续波。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W4/10 已停止且通过。本波创建前不存在 `实施波次/W5/`。
- 未读取、未修改 `tools/`。未改 `ContentView.swift`、`SessionLockQuerying.swift`、`KeyVaultService.swift`、`RevealGate.swift`。
- `FakeRevealGate.swift` 已有 `confirmCombinationWithAppPassword` / `isAppPasswordMaterialSet`，本波未再改。

## 2. 本波实际修改（均在 W5 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `UI/Vault/VaultHomeViewModel.swift` | 新增 `DetailRevealReuse`：授权绑定详情实例 + `keyId`；只有查看成功才建立；复制走已有 `copyRevealedSecret`。 |
| `UI/Vault/KeyDetailView.swift` | 浏览态拆成查看/隐藏与复制；查看成功后明文只留本实例；复制若有授权则不再过门闩；关详情/换 key/进后台/会话锁/进编辑/销毁时清除。编辑仍单独 `revealReturning`，不读取用授权。 |
| `UI/Vault/VaultHomeView.swift` | 详情 `.id(keyId)`，换 key 换实例；列表复制、⌘C 仍走 `beginCopy`，不读详情授权。 |
| `App/AppPrivacyController.swift` | 组合档 `usesCombinationUnlock`；显式「使用应用密码」走 `confirmCombinationWithAppPassword`；未设材料 fail-closed，另有设备主人后设密；生物取消不自动进口令。 |
| `UI/Shared/AppLockCoverView.swift` | 组合档按钮与口令框；用 `EnvironmentObject` 接线，不改 `ContentView`。 |
| `UI/Settings/SettingsView.swift` | 设备验证动态名称 +「推荐」；四档名称；不验证暂停句保留；组合档也可管理应用密码。 |
| `Localizable.xcstrings` | 补推荐、设备动态名、组合档入口、查看/隐藏/辅助功能键；验证方式「应用密码」不再写成「主密码」。 |
| `KeyVaultServiceTests.swift` | `copyRevealedSecretToClipboard` 零身份调用，会话锁仍拒绝。 |
| `RevealGateCoordinatorTests.swift` | 授权正反例：成功查看才建；另一实例/另一 key/先复制再查看不建；七种清除原因失效。 |
| `AppPrivacyControllerTests.swift` | 组合档显式入口、错口令、缺材料、设密、取消设密、空口令。 |

## 3. 产品行为

### 应当复用

同一 `KeyDetailView` 实例、同一 `keyId`：查看成功后立刻复制，调用 `copyRevealedSecret`，不再走 `copySecretToClipboard` 门闩。不设秒数。隐藏明文不撤销授权；进入编辑会撤销。

### 绝不能复用

- 复制后查看、列表复制、⌘C、另一详情实例、另一 key：复制仍走 `beginCopy`。
- 关详情、换 key、`scenePhase == .background`、会话锁（含自动锁）、窗口/`onDisappear`、开始编辑：授权清空。
- 取消/失败/只显示掩码/空明文：不建授权。
- 导出、删除、清空、编辑：不读此授权。

取用关闭或不验证档：查看仍可能直接得到明文；此时授权只表示「本实例已经合法看过」，复制走无门闩剪贴板写入，不伪造一次身份验证。

### 组合档界面

锁屏提供「使用应用密码」。取消 Face ID / Touch ID 不会自动改走口令或设备密码。已设材料则只调 `confirmCombinationWithAppPassword`；未设则口令入口改为先过设备主人再设密，生物识别仍可用于解锁。

**计划缺口（未在 KeyDetail 上做取用组合档按钮）：** 查看/复制的门闩在 `KeyVaultService.confirmRevealIfNeeded` → `CurrentRevealPolicyAuth`。组合档分支忽略传入的应用密码，始终 `gate.confirm(.biometryOrAppPassword)`。W5 清单不含 `SessionLockQuerying.swift` / `KeyVaultService.swift`。若在详情先 `confirmCombinationWithAppPassword` 再 `revealSecret`，生产路径会再弹一次生物识别。因此详情取用没有接这条按钮，避免假闭环。锁屏解锁不经过 KeyVault，本波已接好。

### 本地化

对本波改动文件扫描 `settings.policy.*` / `appLock.combination.*` / `vault.detail.showSecret` 等键，对照 `Localizable.xcstrings`，缺键为 0。真机系统弹窗与三端布局属 W6。

## 4. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线全部通过。`git diff --check` 对本波文件退出 0。

本环境 `xcodebuild test` / `xcodebuild -checkFirstLaunchStatus` 返回 69（Xcode license），未能在本会话跑模拟器测试。Codex 阶段4A 必须独立运行：

```text
xcodebuild test -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/KeyVaultServiceTests \
  -only-testing:ApiRelayTests/AppPrivacyControllerTests \
  -only-testing:ApiRelayTests/RevealGateCoordinatorTests
```

本波新增/加严用例：

| 格子 | 测试 |
| --- | --- |
| 查看成功才建授权；另一实例/另一 key 拒绝 | `testReuseGrantOnlyAfterSuccessfulDisplay` |
| 七种清除原因 | `testReuseGrantClearReasonsInvalidateCopy` |
| 复制后查看不建授权 | `testCopyWithoutDisplayDoesNotEstablishGrant` |
| 已揭示复制零身份、会话锁仍拒绝 | `testCopyRevealedSecretSkipsIdentityAndHonorsSessionLock` |
| 组合档显式入口，不调 `confirmMandatory` | `testCombinationAppPasswordUnlockUsesExplicitCombinationEntry` |
| 错口令保持锁、不走设备主人 | `testCombinationWrongPasswordStaysLockedWithoutDeviceOwner` |
| 缺材料 fail-closed | `testCombinationMissingMaterialDoesNotUnlockOrCallMandatory` |
| 未设则设备主人后设密 | `testCombinationSetupRequiresDeviceOwnerThenSetsPassword` |
| 设密取消不写材料 | `testCombinationSetupCancelStaysLockedWithoutWritingPassword` |
| 空口令不调门闩 | `testCombinationEmptyPasswordDoesNotCallGate` |

未跑共享 scheme 全量测试（W6）。真机 Face ID / Touch ID、分栏手测、快捷键跨窗手测列入 W6。

## 5. 收尾四问

1. **外部资源：** 取用复用把明文放在 `KeyDetailView` 的 `@State`（单次详情生命周期），不进 SwiftData / CloudKit / `@Published`。锁屏组合档设密走本机 `MasterPasswordService`（ThisDeviceOnly `.masterpw`）。测试：`KeychainStore.makeForTests()`、内存 SwiftData、`FakeRevealGate`；`AppLockLaunchCache.resetForTests()` 仍在 `AppPrivacyControllerTests.setUp`。剪贴板测试调用 `copyRevealedSecretToClipboard`，与既有复制测试一样写进程剪贴板，不碰用户生产 Keychain 组。
2. **失败路径：** 查看取消/失败 → 仍是掩码，无授权，可再点查看。应用密码档查看仍走既有主密码 sheet。组合档锁屏：空口令说明为空；错口令「不正确」；未设「本机尚未设置应用密码」，可改走设密（先设备主人）或继续用生物识别；设密太短有独立文案；设密取消保持锁定且不写材料。会话锁下已揭示复制抛 `sessionLocked`。详情组合档「使用应用密码」未接线，用户只能走系统生物识别或（应用密码档）既有口令 sheet。
3. **接缝：** 复用策略是 UI 层纯值类型，测试直接打 `DetailRevealReuse`。锁屏组合档打真实 `AppPrivacyController` + `FakeRevealGate` 日记。`copyRevealedSecretToClipboard` 打生产 `KeyVaultService` + `FakeRevealGate`。未新增 protocol。
4. **文件粒度：** `VaultHomeView.swift` 4519 行、`SettingsView.swift` 1599 行、`VaultHomeViewModel.swift` 1036 行、`AppPrivacyController.swift` 913 行、`KeyDetailView.swift` 661 行、`AppLockCoverView.swift` 现约 400+ 行，均已超 400 行建议。按计划不顺手拆。

## 6. 未验证 / 未做

- 本会话未能运行 `xcodebuild test`（许可证 69）。
- 真机系统弹窗、iPhone/iPad/Mac 布局、VoiceOver/Dynamic Type 手测、双设备同步：W6。
- 详情内查看/复制的组合档「使用应用密码」：见第 3 节计划缺口。若 Codex 判定为阻塞，需要把 `SessionLockQuerying.swift` 的组合档在传入应用密码时改走 `confirmCombinationWithAppPassword`，并重新批准计划后再改。

## 7. 方法观察

W5 把组合档按钮放在锁屏 UI 文件里是够的；把同一按钮接到查看/复制时，真正决定走哪条 `confirm` 的是 W3 的 `CurrentRevealPolicyAuth`。精确文件清单如果只列 UI、不列这条路由，执行者要么越权改引擎，要么留下缺口。本波选择后者并写明，而不是接一条会连弹两次生物识别的假按钮。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
