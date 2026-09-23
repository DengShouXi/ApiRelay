# 阶段4：Grok波次整改报告（W5）

写入状态：未停止

- 阶段：4
- 波次：W5 整改（关闭 `实施波次/W5/06-Codex波次复验报告.md` 的测试证据阻塞）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：已批准的 W5 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W5/05-Grok波次整改报告.md`、`实施波次/W5/06-Codex波次复验报告.md`
- 实际授权：用户执行 `提示词/阶段4-Grok执行下一波.md`。W5/06 `失败类型：普通整改`，要求用户亲自完成许可后只重跑七组目标测试和必要编译。用户已亲自同意 Xcode/Apple SDK 许可并完成 first launch。本轮不覆盖 01—06，不进入 W6，不修改已确认关闭的实现，除非新运行结果给出明确失败证据。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W5/06 已停止，失败类型普通整改。本文件为下一个连续奇数报告。
- `xcodebuild -checkFirstLaunchStatus` 退出码 **0**。
- 未读取、未修改 `tools/`。未进 W6。未改 `KeyVaultService`、四个服务实现、宪法或正式规格。

## 2. 关闭 W5/06 测试证据阻塞

W5/04 的实现阻塞 B1–B4 在 W5/05、W5/06 中已确认关闭。W5/06 唯一未关闭项是：许可未接受，目标测试无法启动。

本轮许可已通过后：

1. 为让 `warnings-as-errors` 能编过，先做 W5 允许文件内的机械编译修正。
2. 第一次七组目标测试：`Executed 130 tests, with 3 failures`。失败全部来自 `KeyVaultServiceTests.testPermanentDeleteRetryRefreshesKeyAccountAndTool` 的 key / account / tool 三种 kind。错口令提交后 `hasPendingSensitiveRetry` 仍为 `true`。
3. 该失败由本轮之前重写的 `VaultHomeViewModel.submitMasterPassword` 引起：只把 `pendingPolicyOperation` 拷到局部变量再 `await`，成功路径靠 `finishSensitiveAuthSuccess()` 清空；错口令走 Fake 应用密码门失败后既不清待办，也不再 `rememberMasterPasswordRetry`。测试要求错口令后待办必须消失，用户须重新发起永久删除，且最后一次多余的正确口令不得泄漏执行。
4. 修复：取出待办后立刻置空 `pendingPolicyOperation` 并关掉 `offerCombinationAppPassword` / 口令页，再执行原操作。组合档设密路径仍先走 `completeCombinationSetupThenRetry`，不会在设密前提前消费待办。未改测试意图去迁就泄漏待办。
5. 重跑同一条七组命令后：`Executed 130 tests, with 0 failures`，`** TEST SUCCEEDED **`。
6. 另做 iOS 模拟器 Debug `xcodebuild build`：`** BUILD SUCCEEDED **`。

W5/06 的测试证据阻塞关闭。

## 3. 本轮实际改动文件（均在修订后 W5 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `UI/Vault/VaultHomeViewModel.swift` | `submitMasterPassword` 提交时消费待办，错口令不再留下可泄漏的重试 |
| `UI/Settings/SettingsView.swift` | 危险区「使用应用密码」在 `if let prefs` 外，改为 `prefs?.revealPolicy ?? .noVerification`，消除未定义 `prefs` |
| `UI/Vault/VaultHomeView.swift` | `onChange(of: selectedKeyId)` 关详情分支改为 `if old != nil, new == nil`，消除未使用绑定 |
| `RevealGateCoordinatorTests.swift` | `await journal` 提到局部变量，避免自动闭包里 `await` 导致 warnings-as-errors |
| `DataLifecycleTests.swift` | 同上 |
| `AppPrivacyControllerTests.swift` | 同上 |
| `KeyVaultServiceTests.swift` | 同上（`testCopyRevealedSecretSkipsIdentityAndHonorsSessionLock`）；未改永久删除重试的断言意图 |
| 本文件 | 本轮证据 |

未改 App 锁已通过部分、未改服务实现、未改 `Localizable.xcstrings`、未改 B1–B4 已关闭的失效接线。

## 4. 测试与编译

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线全部通过。`git diff --check` 退出 0。

```text
xcodebuild test -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  -resultBundlePath /tmp/ApiRelayW5-07.xcresult \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/KeyVaultServiceTests \
  -only-testing:ApiRelayTests/AppPrivacyControllerTests \
  -only-testing:ApiRelayTests/RevealGateCoordinatorTests \
  -only-testing:ApiRelayTests/RecentlyDeletedBatchTests \
  -only-testing:ApiRelayTests/DataLifecycleTests \
  -only-testing:ApiRelayTests/SecureBackupTests \
  -only-testing:ApiRelayTests/ConsumerToolSessionLockTests
```

工作目录：`.../E02_ApiRelay_Github/ApiRelay`。日志：`/tmp/ApiRelayW5-07.log`。

最终运行（待办消费修复之后）：

- 合计：**130 tests, 0 failures**
- 结果包：`/tmp/ApiRelayW5-07.xcresult`
- `AppPrivacyControllerTests` 41 / `ConsumerToolSessionLockTests` 5 / `DataLifecycleTests` 8 / `KeyVaultServiceTests` 33 / `RecentlyDeletedBatchTests` 12 / `RevealGateCoordinatorTests` 13 / `SecureBackupTests` 18
- 修复前同命令：**130 tests, 3 failures**，全部是 `testPermanentDeleteRetryRefreshesKeyAccountAndTool`

```text
xcodebuild -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  build
```

`** BUILD SUCCEEDED **`。日志：`/tmp/ApiRelayW5-07-build.log`。

与 W5 阻塞对应、本轮已实际跑过的用例：

| 阻塞 / 回归 | 测试 |
| --- | --- |
| W5/06 许可后必须给出当前绿结果 | 上表七组合计 130 / 0 |
| 错口令不得留下永久删除待办 | `testPermanentDeleteRetryRefreshesKeyAccountAndTool` |
| B1/B2 无待办不武装；离开/会话锁清待办 | `testCombinationPendingDoesNotArmNextOperationAndClearsOnLeave` |
| B1 绑定原删除仍可口令重试 | `testCombinationRetryBindsOriginalVaultDelete` |
| B3 先建授权再无验证/取消/安全设置变化 | `testUnauthenticatedDisplayAndCancelClearExistingGrant` |
| B4 七个命名生产方法清授权 | `testReuseGrantClearReasonsInvalidateCopyViaProductionSeam` |
| B4 真实事件接线 | `testReuseInvalidationProductionWiringWouldFailIfEventSitesRemoved` |
| B2 清空不走武装捷径 | `testEraseCombinationPasswordUsesExplicitEntryWithoutRepeatingDestructiveConfirm` |

未跑共享 scheme 全量测试、Mac Catalyst Debug/Release 或 W6 人工矩阵。

## 5. 收尾四问

1. **外部资源：** 本轮没有新碰 Keychain / SwiftData / CloudKit / UserDefaults / App Group。永久删除重试测试继续用 `KeychainStore.makeForTests()`、内存 SwiftData、`FakeKeyVault` / `FakeConsumerTools` 的应用密码门，以及未 `start()` 的 `AppPrivacyController`（会话默认 `.noVerification`）。测试隔离与 W4/W5 已有夹具相同。
2. **失败路径：** 提交应用密码会消费当前待办。空白口令在门闩前拒绝且不消费待办。错口令保持原数据、待办消失，用户必须重新点永久删除再提交正确口令。正确口令删除成功后，再提交一次不会泄漏第二次删除。组合档尚未设密时仍先走设密再恢复原待办。取消口令页仍走 `abandonCombinationPending()`。
3. **接缝：** 未新增 protocol。`submitMasterPassword`、`hasPendingSensitiveRetry`、`abandonCombinationPending` 仍可被现有测试直接驱动。
4. **文件粒度：** `VaultHomeView.swift` 4563 行、`SettingsView.swift` 1708 行、`VaultHomeViewModel.swift` 1335 行、`KeyVaultServiceTests.swift` 1153 行、`AppPrivacyControllerTests.swift` 941 行，均已超 400 行建议。按计划不顺手拆。

## 6. 未验证项

- 共享 scheme 全量测试、Mac Catalyst Debug/Release。
- 真机 Face ID / Touch ID、VoiceOver / Dynamic Type、iPhone/iPad/Mac 布局、多窗和双设备同步：仍属 W6。

## 7. 方法观察

许可未接受时不应再送阶段 4A。许可通过后，第一次真实运行立刻暴露「提交口令必须消费待办」；这是 W5 重写 `submitMasterPassword` 的回归，不能用阅读 B1–B4 已关闭来代替跑测试。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
