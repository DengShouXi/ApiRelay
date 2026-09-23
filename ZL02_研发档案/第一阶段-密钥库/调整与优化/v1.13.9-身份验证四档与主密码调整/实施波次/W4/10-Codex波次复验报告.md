# 阶段4A：Codex 波次复验报告（W4）

写入状态：未停止

- 阶段：4A
- 波次：W4
- 审计对象：`实施波次/W4/09-Grok波次整改报告.md` 及其对应本地改动
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 审计方式：Codex 独立只读复验；未修改整改实现

## 1. 入口与边界核对

- W4/09 已以“写入状态：已停止”完成交接，输入为已批准的 `04`、`05`、任务契约和 W4/08。
- 当前分支与 HEAD 符合任务契约；暂存区为空，仓库只有一个 worktree。
- `main`、`origin/main` 和 `release/1.0.0` 未变化。
- `tools/` 仍为未跟踪内容，未读取、修改或纳入本次范围。
- 本轮整改限于 W4 已批准的 `BackupSettingsViews.swift` 与 `SecureBackupTests.swift`，没有进入 W5，也未改变自定义口令或不加密路径的产品语义。
- 同编号偶数审计报告不存在；本报告使用紧随 `09` 的编号 `10`，未覆盖历史证据。

## 2. W4/08 阻塞复验

W4/08 的唯一阻塞是：锁定态测试调用了生产界面没有使用的平行辅助入口，不能约束真实导出、导入调用链。

独立搜索和代码检查确认该阻塞已经关闭：

- `BackupExportView.exportWithStored` 直接调用 `BackupStoredPassphraseAccess.exportUsingStored`。
- `BackupImportView.importWithStored` 直接调用 `BackupStoredPassphraseAccess.importUsingStored`。
- 两项锁定态测试调用的正是上述生产入口共同使用的两个协调方法，不再存在仅供测试调用的平行实现。
- 应用密码重试分别重新进入 `exportWithStored` 和 `importWithStored`，因此会再次经过同一协调方法与会话锁检查，不会拿先前读取的口令绕过锁定检查。

## 3. 关键顺序与正反例

### 已保存口令导出

`exportUsingStored` 先调用 `read`；`read` 先执行 `requireUnlocked`，通过后才读取 `backupPassphrase.plaintext()`，最后才调用 `exportBackup`。锁定态测试证明：不读明文、不触发身份门闩、不调用导出服务，也不产生导出结果。

### 已保存口令导入

`importUsingStored` 首先执行 `requireUnlocked`，随后才允许 `inspectProtection`；确认是口令保护文件后，再通过带锁检查的 `read` 读取已保存口令，最后调用 `importBackup`。锁定态测试证明：不读明文、不检查备份保护类型、不触发身份门闩、不调用导入服务，也不产生导入副作用。

### 范围保持

- 自定义口令和不加密导出/导入继续走原路径，没有被接入已保存口令协调器。
- 备份口令复制仍经统一的带锁 `read` 入口。
- 生产代码中 `backupPassphrase.plaintext()` 的直接调用只有 `BackupStoredPassphraseAccess.read` 一处。

## 4. 独立验证结果

- `bash ApiRelay/scripts/selfcheck.sh`：红线全部通过。
- `git diff --check`：通过。
- 独立运行 `SecureBackupTests`：17 项通过，0 项失败。
- 独立结果：`/tmp/ApiRelayCodexW4Reaudit4DD/Logs/Test/Test-ApiRelay-2026.09.15_11-00-36-+0800.xcresult`。
- Grok 报告中的 70 项组合回归结果与本次独立的 17 项重点复验相互补充；未用 Grok 自述代替本次关键引用和测试检查。

## 5. 阻塞、非阻塞与未验证项

### 阻塞

无。W4/08 指定的测试接缝阻塞已关闭，W4 可以结束。

### 非阻塞建议

- `BackupSettingsViews.swift` 已超过建议文件长度，但拆分不属于本轮授权，不应为此延长 W4。

### 未验证项

- 真机 Face ID / Touch ID、iPhone/iPad/Mac 人工矩阵和共享 scheme 全量测试留到 W6。
- 同一详情取用授权复用、组合档显式“使用应用密码”入口及相关界面属于 W5，尚未开始。

## 6. 方法观察

本轮验证了前次方法观察的整改方式：安全测试接缝不仅要可调用，还必须通过符号引用证明它处在真实生产路径上；确认这一点后，不再为同一问题追加无边界的证明轮次，避免形成递归整改。

下一步负责人：Grok
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`

写入状态：已停止

波次审计通过，可以进入下一波。
