# 阶段4A：Codex波次复验报告（W4）

- 阶段：4A
- 波次：W4（复验 `05-Grok波次整改报告.md`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：用户批准的 W4 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W4/04-Codex波次复验报告.md`、`实施波次/W4/05-Grok波次整改报告.md`、实际 Git 差异与独立测试证据
- 实际授权：用户明确执行阶段4A；本次只读复验 W4，实现文件未由 Codex 修改

## 1. 入口与保护边界

- W4/05 是最早未通过波次的最新奇数 Grok 报告，文末为 `写入状态：已停止`；本报告创建前不存在 W4/06。
- 当前分支和 HEAD 与契约一致；暂存区为空；只有一个 worktree。
- `main`、`origin/main`、`release/1.0.0` 均保持契约登记值；未发现提交、上传、历史改写或 `tools/` 被纳入。
- W4/05 只修改 `BackupSettingsViews.swift` 和 `SecureBackupTests.swift`，都在 W4 精确范围内；未发现提前实施 W5。
- 项目自检红线和 `git diff --check` 均通过。

## 2. 已确认修复

- `BackupPassphraseSensitiveOps.perform` 已把备份口令保存、复制、清除收束到同一入口。
- `BackupCurrentPolicyAuth.confirm` 已在加载偏好和调用任何身份验证之前检查当前会话锁；锁定时返回 `sessionLocked`。
- 新增测试逐项证明保存、复制、清除在锁定态不调用身份门闩，不读写/清除备份口令，不写剪贴板；复制时的身份取消也保持零副作用。
- 因此 W4/04 指出的“备份口令管理自身绕过会话锁”已经关闭。

## 3. 仍然阻塞

### W4-B02：使用已保存备份口令的导出/导入仍在会话锁检查前读取明文

- `05` 的逐操作矩阵不仅包含“备份口令管理”，还分别包含备份导出和导入，并要求会话锁适用时先拒绝敏感入口。
- `BackupExportView.exportWithStored()` 先调用 `environment.backupPassphrase.plaintext()`，取得本机备份口令明文后才调用 `performExport`；会话锁检查位于更后的 `SecureBackupService.exportBackup`。
- `BackupImportView.importBytes(_:)` 在 `.defaultStored` 分支同样先调用 `environment.backupPassphrase.plaintext()`，取得明文后才调用 `importData`；会话锁检查位于更后的 `SecureBackupService.importBackup`。
- 因此会话已经锁定时，最终导出/导入虽然会被服务拒绝，但敏感备份口令已被界面提前读入内存。这不符合“会话锁先拒绝”的安全顺序，也说明 W4 的备份导出/导入生产入口尚未完整接到同一门闩。
- 当前 68 项测试只覆盖服务层导出/导入的当前策略，以及备份口令保存/复制/清除的锁定态；没有执行“锁定态 + 使用已保存口令 + 导出/导入”，所以全绿无法排除上述路径。
- 修复和测试都可限制在已批准的 `BackupSettingsViews.swift` 与 `SecureBackupTests.swift` 内，不需要新增产品决定或扩大 W4 精确范围，属于普通整改。

## 4. 独立验证证据

- Codex 独立运行项目自检：红线全部通过。
- Codex 独立运行 `git diff --check`：通过。
- Codex 使用新的 DerivedData 在 iPhone 17 Pro、iOS 26.5 模拟器复跑五组 W4 测试：68 项通过、0 失败、0 异常。
- 独立结果：`/tmp/ApiRelayCodexW4Reaudit2DD/Logs/Test/Test-ApiRelay-2026.09.15_09-22-53-+0800.xcresult`。
- 静态调用链确认两个提前读取点分别位于 `BackupSettingsViews.swift` 的 `exportWithStored()` 和 `importBytes(_:)`，并且均早于 `SecureBackupService` 的会话锁检查。

## 5. 整改停止点

Grok 下一次只整改本报告指出的 W4-B02 剩余路径：

1. 使用已保存备份口令进行导出或导入时，必须先检查会话锁，锁定态不得调用 `backupPassphrase.plaintext()`、任何身份门闩、导出服务或导入服务。
2. 复用现有安全入口或增加同文件内最小可测试协调接缝；不得把会话锁检查放在读取口令之后。
3. 增加导出、导入两条锁定态测试，分别断言口令明文读取次数为零、身份调用为零、备份服务调用为零，并且不产生导出文件或导入副作用。
4. 不修改 W4 之外文件，不进入 W5，不顺带重构备份页面。

## 6. 非阻塞建议与未验证项

- W4/05 严格完成了上一报告字面列出的保存、复制、清除三项，但审计必须继续沿同一敏感资源检查其它入口；后续整改报告应列出所有 `backupPassphrase.plaintext()` 调用点及其锁定前置，而不是只列新增帮助器的调用者。
- 真机 Face ID/Touch ID、Mac Catalyst、三端手测和共享 scheme 全量测试仍按计划留给 W6。
- W5 的同详情取用复用和组合档显式应用密码入口不在本次范围。

## 7. 方法观察

本轮暴露的是“下游服务有锁，不代表上游准备数据安全”：如果界面在调用受保护服务前先取出敏感明文，下游拒绝只能阻止最终动作，不能阻止秘密被提前读取。今后的敏感操作矩阵应从用户入口检查到第一个秘密读取点，而不能只从最终服务方法开始。

失败类型：普通整改

写入状态：已停止

波次审计不通过，只能整改本波阻塞。
