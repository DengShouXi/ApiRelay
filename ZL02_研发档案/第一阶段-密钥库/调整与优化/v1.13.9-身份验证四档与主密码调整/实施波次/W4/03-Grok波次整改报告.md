# 阶段4：Grok波次整改报告（W4）

写入状态：未停止

- 阶段：4
- 波次：W4（只修 `02-Codex波次审计报告.md` 的 B01–B03；未进入 W5）
- 报告文件：`实施波次/W4/03-Grok波次整改报告.md`（未覆盖 `01` / `02`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：W4修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W4/01-Grok实施报告.md`、`实施波次/W4/02-Codex波次审计报告.md`
- 实际授权：用户明确「同意 W4 修订版 04 和 05」并执行 `提示词/阶段4-Grok执行下一波.md`。W4/02 失败类型为计划修订；较新 `04`/`05` 引用该报告并覆盖缺口。按阶段4例外，只在新版 W4 精确范围内修 B01–B03。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。暂存区空；单一 worktree。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W4/02 已停止。本报告为该波下一个奇数号 `03`。
- 未读取、未修改 `tools/`。未改 W3 三行设置逻辑，未实现 W5 取用复用或组合档按钮。未改 `Localizable.xcstrings`（复用已有 weaken 口令键）。

## 2. 阻塞关闭

### B01 清空应用密码闭环

`SettingsView` 破坏性确认后走 `SettingsEraseAllFlow`：应用密码档只弹口令采集，正确口令才调用 `eraseAllUserData(appPassword:)`；空值/取消不调用删除。设备验证/组合档不弹应用密码，把门闩留给服务层当前方式。不验证只保留破坏性确认。

可观察顺序：`destructiveConfirmed` → `identityPrompt`/`identityStarted` → `eraseStarted`。

### B03 永久删除重试刷新

`permanentlyDeleteKey` / `Account` / `Tool`（及批量永久删除）成功后 `refresh()` 并发送 `trashBundleDidChange`。取消口令用 `cancelMasterPasswordPrompt()`；错误口令不删除、不发通知；成功后再提交一次是空操作。

### B02 两层矩阵

见第 4 节映射。共享路由穷举四档成功/取消/失败；逐操作接线覆盖 05 所列入口。

## 3. 本波实际修改（均在修订后 W4 清单内）

| 文件 | 做什么 |
| --- | --- |
| `UI/Settings/SettingsView.swift` | 清空口令采集与 `SettingsEraseAllFlow` |
| `UI/Vault/VaultHomeViewModel.swift` | 永久删除成功刷新并发通知；取消口令重试 |
| `UI/Vault/VaultHomeView.swift` | 主密码 sheet 先提交再关闭；`trashBundleDidChange` 改为模块内可见 |
| `UI/Settings/BackupSettingsViews.swift` | `BackupCurrentPolicyAuth` 改为模块内，供接线测试 |
| `DebugSupport/Fakes/FakeKeyVault.swift` / `FakeConsumerTools.swift` | 永久删除可按口令闸门失败 |
| `DebugSupport/Fakes/FakeDataLifecycle.swift` | 记录传入的应用密码 |
| 五份既有测试文件 | 共享路由、逐操作接线、清空闭环、永久删除刷新 |

## 4. 操作 × 证据映射

### 第一层：共享当前方式路由

| 格子 | 测试 |
| --- | --- |
| 不验证成功/无身份调用 | `testSharedCurrentPolicyRoutingMatrix` `none-success`；`testEraseFlowSharedRouting…` `.noVerification` |
| 设备验证成功/取消/失败 | 同矩阵 `device-success/cancel/fail` |
| 应用密码缺/成功/取消/失败 | 同矩阵 `master-missing/success/cancel/fail` |
| 组合档成功/取消/失败，不走 `confirmMandatory` | 同矩阵 `combo-*`；清空 `testEraseCombinationUsesConfirmNotAppPasswordPrompt` |
| 备份口令管理走同一路由 | `testBackupPassphraseManagementUsesCurrentPolicy` |

### 第二层：逐操作接线

| 操作 | 测试（档位/口令、取消或失败零副作用、会话锁） |
| --- | --- |
| 查看 | `testSensitiveOperationWiringMatrix` `reveal` × cancel / masterPrompt / sessionLock |
| 复制 | 同上 `copy` |
| 编辑密钥 | 同上 `editKey` |
| 编辑账号 | 同上 `editAccount` |
| 移入回收站 | 同上 `trash` |
| 恢复 | 同上 `restore`；批量 `testBatchRestoreAndPermanentUseCurrentPolicyMatrix` `permanent=false` |
| 单条永久删除 | 同上 `permanent`；刷新 `testPermanentDeleteRetryRefreshesKeyAccountAndTool` |
| 批量永久删除 | `testBatchRestoreAndPermanentUseCurrentPolicyMatrix` `permanent=true` |
| 备份导入/导出 | `testExportImportCurrentPolicyMatrix` |
| 备份口令管理 | `testBackupPassphraseManagementUsesCurrentPolicy` |
| 清空 | `testEraseFlowSharedRoutingDoesNotCallServiceUntilAllowed`；`testEraseMasterPasswordWrongEmptyAndRateLimitLeaveData`；`testEraseMasterPasswordSuccessClearsData`；`testEraseUsesCurrentPolicyAndCancelLeavesData`；`testEraseSessionLockDoesNotConfirm`；`testEraseCombinationUsesConfirmNotAppPasswordPrompt` |
| 使用方删除/恢复/永久删除 | `testToolDeleteRestorePermanentWiring` |

破坏性确认顺序：清空由 `SettingsEraseAllFlow` 日记证明；回收站单条永久删除仍是确认框之后才进 ViewModel，成功后再发 `trashBundleDidChange`。

## 5. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线通过。`git diff --check` 对本波文件退出 0。

```text
xcodebuild test -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/KeyVaultServiceTests \
  -only-testing:ApiRelayTests/RecentlyDeletedBatchTests \
  -only-testing:ApiRelayTests/ConsumerToolSessionLockTests \
  -only-testing:ApiRelayTests/DataLifecycleTests \
  -only-testing:ApiRelayTests/SecureBackupTests
```

**TEST SUCCEEDED**：66 tests, 0 failures（KeyVaultService 31 + RecentlyDeletedBatch 11 + ConsumerToolSessionLock 4 + DataLifecycle 7 + SecureBackup 13）。

xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_08-40-59-+0800.xcresult`。

未跑共享 scheme 全量测试（属 W6）。

## 6. 收尾四问

1. **外部资源**：清空与永久删除仍写 Keychain / SwiftData。测试用 `KeychainStore.makeForTests()` 或 Fake；SwiftData 用内存容器。未改 Keychain ACL/同步，未碰 CloudKit Production。
2. **失败路径**：清空在应用密码档：取消/空口令不调用删除；错口令与限速保留数据；正确口令才删除。永久删除：取消或错口令条目仍在且不刷新；成功后列表通知刷新；二次提交不泄漏。会话锁仍先拒绝。
3. **接缝**：`SettingsEraseAllFlow` 可在 `DataLifecycleTests` 直接驱动。Fake 密钥库/使用方可注入口令闸门，供 ViewModel 刷新测试，不必改生产 Keychain。
4. **文件粒度**：`VaultHomeView.swift` 4517 行，`SettingsView.swift` 1560 行，`VaultHomeViewModel.swift` 1003 行，`KeyVaultServiceTests.swift` 现已超过 400 行。本波不拆。

## 7. 未验证项

- 真机 Face ID / Touch ID、三端破坏性确认手测、共享 scheme 全量（W6）。
- 组合档显式「使用应用密码」与取用授权复用（W5）。

## 8. 方法观察

服务层拒绝空口令不等于产品流程可完成，这是 B01 的根因。整改测试若在同一 `@ModelActor` 上先按不验证写入、再改偏好，会出现读到旧策略、门闩被跳过的假绿；策略变更后必须换新的服务实例再测被保护操作。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
