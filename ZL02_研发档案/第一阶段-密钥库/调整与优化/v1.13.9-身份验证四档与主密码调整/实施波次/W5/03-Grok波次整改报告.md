# 阶段4：Grok波次整改报告（W5）

写入状态：未停止

- 阶段：4
- 波次：W5 整改（关闭 `实施波次/W5/02-Codex波次审计报告.md` 三个阻塞）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：用户明确批准的 W5 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W5/01-Grok实施报告.md`、`实施波次/W5/02-Codex波次审计报告.md`
- 实际授权：用户明确批准当前 W5 修订版 04/05，并执行 `提示词/阶段4-Grok执行下一波.md`。失败类型为计划修订；较新 04/05 已引用 W5/02 并覆盖缺口。本轮只修该报告三个阻塞，创建本文件，不覆盖 01/02，不进入 W6。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W5/01 已停止；W5/02 判定计划修订且已停止。本文件为下一个连续奇数报告。
- 未读取、未修改 `tools/`。未改 `RecentlyDeletedBatchService` / `ConsumerToolService` / `SecureBackupService` / `DataLifecycleService`（现有 `appPassword` 透传已够）。未改 `KeyVaultService.swift` / `KeyVaultServing.swift`（现有返回值足以证明「本次取用确已验证」）。

## 2. 关闭 W5/02 三个阻塞

### B1 组合档入口不只锁屏

`CurrentRevealPolicyAuth` 现为普通敏感操作唯一分流权威：

- `appPassword == nil` → 只 `confirm(.biometryOrAppPassword)` 一次。
- 用户提交非空口令 → 只 `confirmCombinationWithAppPassword` 一次，不再弹生物 / 设备主人 / `confirmWithMasterPassword`。
- 空白口令在调门闩前拒绝（`combination_password_empty`）。
- 生物取消 / 不可用 / 锁定不自动改走口令或设备密码；显式口令失败不二弹生物识别。

生产调用 `confirmCombinationWithAppPassword` 现有两处表面：App 锁（`AppPrivacyController`）与共享路由（`CurrentRevealPolicyAuth`，供 Vault / 备份 / 设置 / 回收站等透传）。

### B2 伪授权

明文显示（`KeyDetailView.displayedSecret`）与复用授权（`VaultHomeViewModel.detailRevealReuse`）分离。只有取用开启、当前方式不是不验证、且本次查看确已完成身份验证时才 `applyDetailRevealReuse(.authenticatedViewSucceeded)`。不验证或取用关闭可以显示/复制，授权保持空。

### B3 失效证据必须是生产接缝

`KeyDetailView` 真实事件调用 `VaultHomeViewModel.clearDetailRevealReuse(_:)` / `applyDetailRevealReuse`。测试 `testReuseGrantClearReasonsInvalidateCopyViaProductionSeam` 对七种原因逐项驱动该接缝，禁止测试局部变量手动置空。

## 3. 用户入口 → 显式选择 → 共享路由 → 原操作重试 → 证据

| 表面 | 用户入口 | 显式选择 | 共享路由 | 原操作重试 | 证据 |
| --- | --- | --- | --- | --- | --- |
| App 锁 | 锁屏「使用应用密码」 | `beginCombinationAppPasswordEntry` / `unlockWithCombinationAppPassword` | 锁屏直接 `gate.confirmCombinationWithAppPassword`（不经 KeyVault） | 解锁同一待办 | W5/01 已有 `AppPrivacyControllerTests` 组合档用例（保留） |
| Vault 详情查看/复制 | 详情「使用应用密码」 | `VaultHomeViewModel.beginCombinationAppPasswordEntry` | `CurrentRevealPolicyAuth` | `prepareSensitiveAuth` 绑定 `revealReturning` / `copyReturning`，提交口令后同一入口 | `testCombinationRetryBindsOriginalVaultDelete`；`testCombinationPasswordRevealAndDeleteUseExplicitEntry` |
| Vault 编辑/回收站/使用方 | 列表底部「使用应用密码」 | 同上 | 同上 | `editKey` / `updateAccount` / `renameTool` / 移入回收站 / 恢复 / 单条与批量永久删除均在入口绑定原参数 | `testCombinationRetryBindsOriginalVaultDelete`；`testBatchCombinationPasswordUsesExplicitEntry`；`testCombinationPasswordUsesExplicitEntry`（使用方） |
| 备份 | 口令页 / 导出 / 导入「使用应用密码」 | `beginBackupCombinationPassword` 等 | `BackupCurrentPolicyAuth` → `CurrentRevealPolicyAuth` | `pendingAuth` / `pendingStoredExport` / `pendingImport` 绑定后重试；备份文件口令与应用密码仍两套 | `testExportCombinationPasswordUsesExplicitEntry` |
| 设置降低安全/换档 | 验证方式区「使用应用密码」 | `beginSettingsCombinationPassword` | `persistSyncedPatchAsync` 空口令走生物，提交口令走组合档 | `pendingWeakenPatch` 保留原补丁，不重复破坏性确认 | 路由：`testCombinationConfirmWithPasswordUsesExplicitEntryOnce`；空口令不再把 `""` 传进组合档 |
| 设置清空 | 危险区「使用应用密码」 | 同上；破坏性确认后 Face ID 取消只 `combinationOffer` | `SettingsEraseAllFlow.afterCombinationBiometricEnded` → 口令 → `eraseAllUserData(appPassword:)` | 破坏性确认只记一次，再身份验证再删除 | `testEraseCombinationPasswordUsesExplicitEntryWithoutRepeatingDestructiveConfirm` |

缺材料：Vault / 设置 / 备份点「使用应用密码」时若 `isAppPasswordMaterialSet == false`，改为 `confirmMandatory` 后 `setPassword`，取消/失败不写材料、不执行原操作。锁屏设密仍走 W5/01 已通过路径。

## 4. 本轮修改文件（均在修订后 W5 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `Business/System/SessionLockQuerying.swift` | 仅修 `CurrentRevealPolicyAuth`；新增 `CombinationExplicitAuth` |
| `UI/Vault/VaultHomeViewModel.swift` | 授权生产接缝；组合档待办绑定/设密/重试 |
| `UI/Vault/KeyDetailView.swift` | 显示态与授权分离；详情组合档按钮；清除走 ViewModel |
| `UI/Vault/VaultHomeView.swift` | 关详情/换 key 清除；列表复制/⌘C 不读授权；组合档口令页与入口 |
| `UI/Settings/SettingsView.swift` | 降低安全传 `nil` 而非空串；清空组合档待办；两处入口 |
| `UI/Settings/BackupSettingsViews.swift` | 备份三类页组合档入口与待办 |
| `DebugSupport/Fakes/FakeRevealGate.swift` | 仅加 `clearFailure`（测试可解除预编程失败） |
| `KeyVaultServiceTests.swift` | 组合档显式口令走 `confirmCombinationWithAppPassword` |
| `RecentlyDeletedBatchTests.swift` | 批量恢复显式口令 |
| `ConsumerToolSessionLockTests.swift` | 使用方删除显式口令 |
| `DataLifecycleTests.swift` | 清空不重复确认 + 显式口令 |
| `SecureBackupTests.swift` | 导出显式口令 |
| `RevealGateCoordinatorTests.swift` | 共享路由穷举、伪授权、生产清除接缝、Vault 待办重试 |

未改服务实现文件。未改 `Localizable.xcstrings`（复用 `appLock.useAppPassword` 等已有键）。

## 5. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线全部通过。`git diff --check` 对本轮文件退出 0。

本环境 `xcodebuild test` 返回 **69**（尚未接受 Xcode/Apple SDK 许可）。按 05：这是阻塞，不得用 `sudo`、不得用旧 xcresult 冒充。Codex 阶段 4A 必须在已接受许可的环境独立运行：

```text
xcodebuild test -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/KeyVaultServiceTests \
  -only-testing:ApiRelayTests/AppPrivacyControllerTests \
  -only-testing:ApiRelayTests/RevealGateCoordinatorTests \
  -only-testing:ApiRelayTests/RecentlyDeletedBatchTests \
  -only-testing:ApiRelayTests/DataLifecycleTests \
  -only-testing:ApiRelayTests/SecureBackupTests \
  -only-testing:ApiRelayTests/ConsumerToolSessionLockTests
```

本轮新增/加严用例与阻塞对应：

| 阻塞 | 测试 |
| --- | --- |
| B1 共享路由无口令只走纯生物 | `testCombinationConfirmWithoutPasswordUsesBiometricsOnce` |
| B1 显式非空口令只走组合档入口 | `testCombinationConfirmWithPasswordUsesExplicitEntryOnce` |
| B1 空白拒绝且零门闩 | `testCombinationEmptyPasswordRejectedBeforeGate` |
| B1 取消不回落设备密码 | `testCombinationOfferAfterCancelDoesNotFallbackToDevicePassword` |
| B1 Vault 绑定原删除并重试 | `testCombinationRetryBindsOriginalVaultDelete` |
| B1 查看/删除生产服务 | `testCombinationPasswordRevealAndDeleteUseExplicitEntry` |
| B1 回收站 | `testBatchCombinationPasswordUsesExplicitEntry` |
| B1 使用方 | `ConsumerToolSessionLockTests.testCombinationPasswordUsesExplicitEntry` |
| B1 备份 | `testExportCombinationPasswordUsesExplicitEntry` |
| B1 清空不重复破坏性确认 | `testEraseCombinationPasswordUsesExplicitEntryWithoutRepeatingDestructiveConfirm` |
| B2 未验证不得建授权 | `testReuseGrantOnlyAfterSuccessfulAuthenticatedDisplay`；`testUnauthenticatedDisplayEventDoesNotCreateGrant` |
| B3 七种原因走生产接缝 | `testReuseGrantClearReasonsInvalidateCopyViaProductionSeam` |

未跑共享 scheme 全量测试（W6）。真机 Face ID / Touch ID、VoiceOver / Dynamic Type、三端布局列入 W6。

## 6. 收尾四问

1. **外部资源：** 组合档设密仍走本机 `MasterPasswordService`（ThisDeviceOnly `.masterpw`）。取用复用明文只在详情 `@State` 与 ViewModel 授权值（单次详情生命周期），不进 SwiftData / CloudKit / 日志。测试：`KeychainStore.makeForTests()`、内存 SwiftData、`FakeRevealGate`；`AppLockLaunchCache.resetForTests` 仍在既有 `AppPrivacyControllerTests.setUp`。剪贴板测试与 W5/01 相同，不碰用户生产 Keychain 组。
2. **失败路径：** 生物取消 → 操作未执行，可点「使用应用密码」重试同一待办；口令页取消 / 会话锁 / 界面消失清空待办。空白口令当场拒绝。错口令保持原数据。缺材料：先设备主人再设密，取消不写材料、不执行原操作。不验证/取用关闭：可看可复制，无「已验证授权」。
3. **接缝：** 未新增 protocol。`CombinationExplicitAuth` / `DetailRevealReuseEvent` / `SettingsEraseAllFlow.afterCombinationBiometricEnded` / `BackupCombinationRetry` 均可被测试直接驱动。`FakeRevealGate` 仍覆盖 `confirmCombinationWithAppPassword`。
4. **文件粒度：** `VaultHomeView.swift` 约 4556 行、`SettingsView.swift` 约 1706 行、`VaultHomeViewModel.swift` 约 1308 行、`BackupSettingsViews.swift` 约 1067 行、`KeyDetailView.swift` 约 697 行，均已超 400 行建议。按计划不顺手拆。

## 7. 未验证 / 阻塞

- **环境阻塞：** `xcodebuild test` 退出码 69（Xcode license）。本轮没有可由 Grok 确认的编译与目标测试绿结果。Codex 不得用阅读或本报告自述替代运行。
- 真机系统弹窗、iPhone/iPad/Mac 布局、VoiceOver/Dynamic Type、双设备同步：W6。

## 8. 方法观察

计划修订后把分流权威和四类界面待办写进同一波精确清单，整改才能一次接上，而不必再为每个按钮复制门闩。环境许可 69 仍会让「代码已改」和「审计可运行」分成两截，检查计划把许可失败标成阻塞是必要的。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
