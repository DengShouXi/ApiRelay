# 阶段4：Grok波次整改报告（W4）

写入状态：未停止

- 阶段：4
- 波次：W4（只修 `08-Codex波次复验报告.md` 的测试接缝阻塞；未进入 W5）
- 报告文件：`实施波次/W4/09-Grok波次整改报告.md`（未覆盖 `01`–`08`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：用户已批准的 W4 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W4/08-Codex波次复验报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W4/08 `失败类型：普通整改`，按阶段4只修该报告列出的本波阻塞。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。暂存区空；单一 worktree。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W4/08 已停止。本报告为该波下一个奇数号 `09`。
- 只改 `BackupSettingsViews.swift` 与 `SecureBackupTests.swift`。未进入 W5。未改自定义口令或不加密路径的语义。

## 2. 阻塞关闭

W4/08：测试只打测试专用辅助方法，真实界面另走 `read` 再 `performExport` / `importData`。

现已把真实入口接到同一协调器：

| 生产入口 | 协调入口 | 测试 |
| --- | --- | --- |
| `BackupExportView.exportWithStored`（含应用密码重试） | `BackupStoredPassphraseAccess.exportUsingStored` | `testExportUsingStoredPassphraseSessionLockDoesNotReadSecret` |
| `BackupImportView.importBytes` 在 `.defaultStored` → `importWithStored`（含应用密码重试） | `BackupStoredPassphraseAccess.importUsingStored` | `testImportUsingStoredPassphraseSessionLockDoesNotReadSecret` |

`exportUsingStored` / `importUsingStored` 不再是测试专用。锁定时这两个方法在 `plaintext`、身份门闩、`inspectProtection`、`exportBackup`、`importBackup` 之前抛 `sessionLocked`。应用密码重试也再次走同一入口，不再拿已经读出的口令去调无锁服务。

自定义口令与不加密仍走原来的 `performExport` / `importData`，不经过已存口令协调器。

## 3. 本波实际修改

| 文件 | 做什么 |
| --- | --- |
| `UI/Settings/BackupSettingsViews.swift` | 已存口令导出/导入改为调用协调器；重试不再跳过锁 |
| `ApiRelayTests/.../SecureBackupTests.swift` | 注明测试打的就是上述生产协调入口 |

## 4. 测试

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

**TEST SUCCEEDED**：70 tests, 0 failures（KeyVaultService 31 + RecentlyDeletedBatch 11 + ConsumerToolSessionLock 4 + DataLifecycle 7 + SecureBackup 17）。

xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_10-57-18-+0800.xcresult`。

未跑共享 scheme 全量（属 W6）。

## 5. 收尾四问

1. **外部资源**：本轮只读会话锁标志，不写 Keychain / SwiftData / CloudKit。测试仍用 `FakeBackupPassphrase`、`FakeSecureBackup`、`FakeRevealGate`；锁定态用 `launchAppLockEnabled`，前后 `AppLockLaunchCache.resetForTests()`。
2. **失败路径**：会话已锁时已存口令导出/导入得到 `sessionLocked`，不读明文、不弹身份、不调用备份服务。未保护备份选已存口令时仍提示不匹配。应用密码重试再次检查会话锁。
3. **接缝**：测试调用的 `exportUsingStored` / `importUsingStored` 即生产 `exportWithStored` / `importWithStored` 所用方法。
4. **文件粒度**：`BackupSettingsViews.swift` 874 行，已超过 400 行。本波不拆。

## 6. 未验证项

- 真机 Face ID / Touch ID、三端手测、共享 scheme 全量（W6）。
- 组合档显式「使用应用密码」与取用授权复用（W5）。
- 自定义口令/不加密导出导入仍由服务层会话锁兜底，本轮按停止点未改其界面准备顺序。

## 7. 方法观察

可测试辅助方法必须被生产入口实际调用，否则锁定态测试只能证明平行实现。审计应同时核对符号引用，不能只看测试名字。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
