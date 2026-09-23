# 阶段4：Grok波次整改报告（W4）

写入状态：未停止

- 阶段：4
- 波次：W4（只修 `06-Codex波次复验报告.md` 的剩余 W4-B02；未进入 W5）
- 报告文件：`实施波次/W4/07-Grok波次整改报告.md`（未覆盖 `01`–`06`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：用户已批准的 W4 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W4/06-Codex波次复验报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W4/06 `失败类型：普通整改`，按阶段4只修该报告列出的本波阻塞。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。暂存区空；单一 worktree。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W4/06 已停止。本报告为该波下一个奇数号 `07`。
- 只改 `BackupSettingsViews.swift` 与 `SecureBackupTests.swift`。未进入 W5。

## 2. 阻塞关闭

W4/06 剩余 **W4-B02**：使用已保存备份口令导出/导入时，界面在会话锁检查前读取明文。

新增 `BackupStoredPassphraseAccess`：先检查 `session.isSessionLocked`，锁定则抛 `sessionLocked`，之后才允许 `plaintext()`。导出走 `read` 再进原有 `performExport`；导入在 `.defaultStored` 于 `inspectProtection` 之前就 `requireUnlocked`，读口令也只走 `read`。

测试驱动 `exportUsingStored` / `importUsingStored`：锁定时明文读取、身份门闩、导出/导入/inspect 次数均为零。

## 3. 本波实际修改

| 文件 | 做什么 |
| --- | --- |
| `UI/Settings/BackupSettingsViews.swift` | `BackupStoredPassphraseAccess`；导出/导入/复制读明文前先锁 |
| `ApiRelayTests/.../SecureBackupTests.swift` | 导出、导入两条锁定态零副作用 |

## 4. `backupPassphrase.plaintext()` 调用点

生产文件里现在只有一处直接调用：`BackupStoredPassphraseAccess.read`，其前置是 `requireUnlocked`。

| 入口 | 是否直接 plaintext | 锁定前置 |
| --- | --- | --- |
| 备份口令复制 | 否，经 `read` | `BackupCurrentPolicyAuth.confirm` 先锁，再 `read` 再锁 |
| 备份口令保存/清除 | 不读明文 | `confirm` 先锁 |
| 导出 · 使用已存口令 | 否，经 `read` | `read` 先锁，失败则不调用 `exportBackup` |
| 导入 · 使用已存口令 | 否，经 `read` | 先 `requireUnlocked`，再 `inspectProtection`，再 `read` |
| 导出/导入 · 自定义口令或不加密 | 不读已存口令 | 服务层仍有会话锁；本轮不改这些路径的准备数据 |

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

**TEST SUCCEEDED**：70 tests, 0 failures（KeyVaultService 31 + RecentlyDeletedBatch 11 + ConsumerToolSessionLock 4 + DataLifecycle 7 + SecureBackup 17）。相对 W4/06 的 68 项，本轮新增 2 项。

xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_09-30-32-+0800.xcresult`。

| 格子 | 测试 |
| --- | --- |
| 导出 · 已存口令 · 会话锁 | `testExportUsingStoredPassphraseSessionLockDoesNotReadSecret` |
| 导入 · 已存口令 · 会话锁 | `testImportUsingStoredPassphraseSessionLockDoesNotReadSecret` |

未跑共享 scheme 全量（属 W6）。

## 6. 收尾四问

1. **外部资源**：本轮只读会话锁标志，不写 Keychain / SwiftData / CloudKit。测试用 `FakeBackupPassphrase`、`FakeSecureBackup`、`FakeRevealGate`；锁定态用 `launchAppLockEnabled`，前后 `AppLockLaunchCache.resetForTests()`。
2. **失败路径**：会话已锁时使用已存口令导出/导入得到 `sessionLocked`，不读明文、不弹身份、不调用备份服务。口令仍留在假存储中。其它备份错误仍走原状态文案。
3. **接缝**：`BackupStoredPassphraseAccess` 可在测试中直接驱动；备份服务与口令均为 Fake。
4. **文件粒度**：`BackupSettingsViews.swift` 806 行，已超过 400 行。本波不拆。

## 7. 未验证项

- 真机 Face ID / Touch ID、三端手测、共享 scheme 全量（W6）。
- 组合档显式「使用应用密码」与取用授权复用（W5）。
- 自定义口令/不加密导出导入的界面层锁定前置仍依赖服务层拒绝，本轮按审计停止点未改。

## 8. 方法观察

下游服务有会话锁，不能证明上游准备数据安全。敏感操作矩阵必须从用户入口检查到第一个秘密读取点，而不能只从最终 `exportBackup` / `importBackup` 开始。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
