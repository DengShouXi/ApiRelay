# W5集中检查与直接修复

- 阶段：4A检查后按用户授权转直接实施；不是对自身修复的独立签字
- 修订ID：U2
- 计划修订：U2-R1
- 时间：2026-09-15
- 分支：v1.13.9
- HEAD：6ec5ff7c67547637bbd55f528276422395e28c03
- 方法版本：MAIC-1.3
- 输入：W3/10、W5/09、04/05的U2及U2-R1要求、实际四类入口/测试/本地化
- 实际授权：用户执行阶段4A，并明确“如果还存在什么问题，立刻帮我修复了”；允许本阶段内必要修复，不提交上传。
- 写入状态：已停止

## 一、恢复与本次处理

W3/10为Grok对Codex直接修复的有效独立通过记录，W3关闭，不重新审核自己的09。当前待办为U2-W5/09，报告文末已停止；开始时无W5/10，旧01—08保留。本次检查后直接修复，不再只开一个失败报告让用户转交。

已确认Grok普通组合档入口去设密、缺材料丢待办的改动；本次另修：

1. Vault普通操作仅应用密码档缺材料时，预先拒绝并提供独立恢复，清密码框/待办，不把不存在的密码留在普通操作中要求输入。组合档仍可走纯生物，不机械要求它有材料才能普通使用。
2. 组合档密码入口异步查询回来后再次确认仍有绑定操作，防止已经取消后重新弹框。
3. Vault独立恢复失败将控制器错误回传到当前错误提示，并保留可重试入口，不静默丢提示。
4. 备份管理的当前方式确认在仅应用密码且缺材料时明确拒绝；备份口令、导出、导入共五处捕获缺材料错误，清原待办、关闭普通密码框、显示独立恢复。不自动重试原保存/导出/导入。
5. 备份恢复按钮防重入，保留结果显示；不在点击后立即隐藏整个组件。失败显示错误，取消不伪报成功，设备策略实际保存后才显示恢复结果。
6. W5/09承认曾整文件回退本地化。实查发现22个中文旧“主密码”提示及旧自动解锁说明，已局部修正为应用密码和显式恢复/另行解锁语义，英文对应名称同步修正；内部MasterPassword/存储符号不改。不能证明丢失前全部历史译句逐字恢复，因此不伪称完整历史恢复；当前代码使用的相关精确提示键已扫描，无缺失（排除两个非本地化存储标识）。

修改文件：VaultHomeViewModel.swift、BackupSettingsViews.swift、Localizable.xcstrings、RevealGateCoordinatorTests.swift、SecureBackupTests.swift。均属于原W5范围；没有改服务透传、模型、算法、Keychain、tools或工程manifest。

## 二、实际验证

新增行为测试：testMasterOnlyMissingMaterialOffersRecoveryWithoutBusinessRetry、testBackupMasterOnlyMissingMaterialIsNotPasswordPrompt。已有源码扫描作为附加防线，不当作真实全部界面证据。

首次相关回归141通过、1失败；失败为testBackupPassphraseManagementUsesCurrentPolicy的“已有密码”分支没有设置Fake材料状态，仍断言未设材料会提示旧密码。已补正确已有材料前置状态，而不是放松产品拒绝检查。失败原始证据`/tmp/ApiRelayCodexW5DirectFix.xcresult`保留。

修正后重新实际运行RevealGateCoordinatorTests、AppPrivacyControllerTests、KeyVaultServiceTests、SecureBackupTests、SecuritySettingsPersistTests、SecurityPolicyChangeTests：`/tmp/ApiRelayCodexW5DirectFixFinal.xcresult`。摘要独立读取，iPhone17 Pro iOS26.5模拟器142通过、0失败、0跳过，命令退出0。红线自检退出0、git diff --check通过。

HEAD/main/origin-main/release标签对象保持契约基线；单worktree、暂存空，无提交上传。累计工作区修改属于此前多波，报告只明确本轮补丁，不伪称全部脏文件可归因于本轮。

## 三、剩余真实限制与接力

本次已修复已发现问题，不宣称没有任何潜在问题。三端实际导航/系统弹窗、多窗、双设备CloudKit及原W6/02证据闸门仍需W6，不是让下一阶段替我们修上述已知代码问题。不能保证已被回退的所有历史翻译原文可恢复；本轮确保当前相关提示键/用词与恢复语义一致。

这份报告包含Codex实施者自测，不使用“独立审计通过”结论。W5/11只由Grok集中只读复核本次补丁及现有09；通过后才W6。不会让Codex重复自审，也不重新修W3已关闭缺口。

方法观察：用户已明确允许同阶段直接修复，检查应闭环真实缺陷并运行回归，不把一个缺陷拆成多次用户接力。翻译文件被整体回退不能靠“键存在”证明旧词正确，须同时查实际显示语义。保留真实失败与修正记录，不伪造一次全绿。

下一步负责人：Grok；是否需要用户批准：否，仅独立只读复核，不自动执行。
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4F-Grok集中修复独立复核.md`

本阶段已发现问题直接修复完成，142项相关回归通过；等待独立复核，不是最终验收。
