# 阶段4：Grok波次整改报告（W5）

写入状态：未停止

- 阶段：4
- 波次：W5 整改（关闭 `实施波次/W5/04-Codex波次复验报告.md` 五个阻塞）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：已批准的 W5 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W5/03-Grok波次整改报告.md`、`实施波次/W5/04-Codex波次复验报告.md`
- 实际授权：用户执行 `提示词/阶段4-Grok执行下一波.md`。W5/04 `失败类型：普通整改`，明确写不需要再开计划修订。W5 修订版 04/05 已在上一轮用户消息中批准并用于 W5/03。本轮只修该复验报告列出的本波阻塞，创建本文件，不覆盖 01—04，不进入 W6。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W5/04 已停止，失败类型普通整改。本文件为下一个连续奇数报告。
- 未读取、未修改 `tools/`。未改服务实现文件，未进 W6。

## 2. 关闭 W5/04 五个阻塞

### B1 待办不得离开原场景后遗留

`VaultHomeViewModel.abandonCombinationPending()` 取消进行中的门闩并清空待办、口令页和路由偏好。关详情、换 key、离前台、窗口销毁、开始编辑、自动锁、会话锁都走对应 `invalidateRevealReuse*`；切页另调 `abandonCombinationPending()`。设置页 `onDisappear` 清 `pendingWeakenPatch` / `eraseAwaitingIdentity`；备份三类页 `onDisappear` 清各自 pending。取消口令页仍走 `cancelMasterPasswordPrompt()`。

### B2 去掉无待办的「武装下一次」

`CombinationExplicitAuth.shouldShowExplicitEntry(hasBoundOperation:policy:)` 是四类界面同一规则：没有已绑定当前操作就不显示「使用应用密码」。点按钮只打开当前待办的口令页；无待办时 `beginCombinationAppPasswordEntry` 是空操作。已删除 `combinationPrefersPassword` 及设置清空的 `prefersCombinationPassword` 捷径。App 锁封面仍显示该按钮，因为锁屏本身就是当前解锁待办。

### B3 无验证/取消/失败/安全设置变化必须清旧授权

`applyDetailRevealReuse(.unauthenticatedDisplay)` 与 `.viewCancelledOrFailed` 现将授权置空。查看取消或失败走后者。安全偏好持久成功后，`VaultHomeView` 调 `invalidateRevealReuseForSecuritySettingsChange()`。

### B4 七种失效必须能因接线回归而失败

每种原因有独立生产方法：`invalidateRevealReuseCloseDetail` / `SwitchKey` / `LeaveForeground` / `AutoLock` / `SessionLock` / `WindowDestroyed` / `BeginEdit`。界面事件直接调用这些方法；自动锁与会话锁仍汇入 `handleSessionLocked()`。`testReuseGrantClearReasonsInvalidateCopyViaProductionSeam` 分别调用这七个方法，不再枚举 reason 后调通用清除。`testReuseInvalidationProductionWiringWouldFailIfEventSitesRemoved` 读取 `KeyDetailView.swift` 与 `VaultHomeView.swift` 源码，断言事件点包含这些生产符号；删掉任一接线会使该测试失败。

### B5 目标测试仍无当前可运行证据

本环境 `xcodebuild test` 退出码 **69**（尚未接受 Xcode/Apple SDK 许可）。未使用 `sudo`，未用旧 xcresult 冒充。Codex 阶段 4A 必须在已接受许可的环境独立重跑。

## 3. 本轮修改文件（均在修订后 W5 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `Business/System/SessionLockQuerying.swift` | `shouldShowExplicitEntry` |
| `UI/Vault/VaultHomeViewModel.swift` | 待办放弃、七个失效方法、无验证/失败清授权 |
| `UI/Vault/KeyDetailView.swift` | 事件点调用命名失效方法；按钮仅在有待办时显示 |
| `UI/Vault/VaultHomeView.swift` | 关详情/换 key/切页/安全设置变化；列表按钮仅有待办时显示 |
| `UI/Settings/SettingsView.swift` | 设置/清空按钮仅有待办；离开即清；去掉武装下一次 |
| `UI/Settings/BackupSettingsViews.swift` | 备份三类页同上 |
| `RevealGateCoordinatorTests.swift` | 待办放弃、旧授权清除、七方法行为、源码配线 |
| `DataLifecycleTests.swift` | 清空不再走 prefersCombinationPassword 捷径 |

未改 App 锁已通过部分、未改 `KeyVaultService` / 四个服务实现、未改 `Localizable.xcstrings`。

## 4. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线全部通过。`git diff --check` 对本轮文件退出 0。

```text
xcodebuild test ... -only-testing:ApiRelayTests/{KeyVaultServiceTests,AppPrivacyControllerTests,RevealGateCoordinatorTests,RecentlyDeletedBatchTests,DataLifecycleTests,SecureBackupTests,ConsumerToolSessionLockTests}
```

退出码 **69**。精确测试数、失败数和本轮 xcresult 路径：无（测试未启动）。

本轮与阻塞对应的用例：

| 阻塞 | 测试 |
| --- | --- |
| B1/B2 无待办不武装；离开/会话锁清待办 | `testCombinationPendingDoesNotArmNextOperationAndClearsOnLeave` |
| B2 显示规则 | 同上中的 `shouldShowExplicitEntry` |
| B3 先建授权再无验证/取消/安全设置变化 | `testUnauthenticatedDisplayAndCancelClearExistingGrant` |
| B4 七个命名生产方法清授权 | `testReuseGrantClearReasonsInvalidateCopyViaProductionSeam` |
| B4 真实事件接线 | `testReuseInvalidationProductionWiringWouldFailIfEventSitesRemoved` |
| B1 绑定原删除仍可口令重试 | `testCombinationRetryBindsOriginalVaultDelete`（保留） |
| B2 清空不走武装捷径 | `testEraseCombinationPasswordUsesExplicitEntryWithoutRepeatingDestructiveConfirm` |

未跑共享 scheme 全量测试（W6）。真机 Face ID / Touch ID、VoiceOver / Dynamic Type、三端布局列入 W6。

## 5. 收尾四问

1. **外部资源：** 组合档设密仍走本机 `MasterPasswordService`（ThisDeviceOnly `.masterpw`）。取用复用明文只在详情 `@State` 与 ViewModel 授权值，不进 SwiftData / CloudKit / 日志。测试：`KeychainStore.makeForTests()`、内存 SwiftData、`FakeRevealGate`。源码配线测试只读仓库内 Swift 文件，不碰用户生产 Keychain 组。
2. **失败路径：** 生物取消后，只有仍停在原场景且待办还在时才出现「使用应用密码」。关详情、换 key、切页、窗口销毁、会话锁或口令页取消后待办消失，不会把已离开的删除/恢复/编辑延迟执行。无待办点按钮无反馈、也不武装下一次。空白口令仍在门闩前拒绝。错口令保持原数据。
3. **接缝：** 未新增 protocol。`abandonCombinationPending`、七个 `invalidateRevealReuse*`、`CombinationExplicitAuth.shouldShowExplicitEntry`、`SettingsEraseAllFlow.afterCombinationBiometricEnded` 均可被测试直接驱动；配线测试绑定 UI 源文件中的生产符号。
4. **文件粒度：** `VaultHomeView.swift` 4563 行、`SettingsView.swift` 1708 行、`VaultHomeViewModel.swift` 1333 行、`BackupSettingsViews.swift` 1053 行、`KeyDetailView.swift` 698 行，均已超 400 行建议。按计划不顺手拆。

## 6. 未验证 / 阻塞

- **环境阻塞：** `xcodebuild test` 退出码 69（Xcode license）。本轮没有可由 Grok 确认的编译与目标测试绿结果。Codex 不得用阅读或本报告自述替代运行。
- 真机系统弹窗、iPhone/iPad/Mac 布局、VoiceOver/Dynamic Type、双设备同步：W6。

## 7. 方法观察

通用 `clear(reason)` 只能证明清除函数本身，不能证明界面还在调用它。把七种失效写成界面必须点名的生产方法，再用源文件断言这些符号出现在事件点，才能在接线被删时失败。待办泄漏属于同一类问题：只测「取消后立即重试成功」看不到离开场景后的错操作。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
