# Codex直接修复：W3/08偏好条件提交缺口

- 阶段：4（用户授权执行者改为Codex，非独立审计）
- 修订ID：U2
- 计划修订：U2-R1
- 时间：2026-09-15
- 分支：v1.13.9
- HEAD：6ec5ff7c67547637bbd55f528276422395e28c03
- 方法版本：MAIC-1.3
- 输入：W3/08、实际PreferencesService/UserPreferencesRepository及测试
- 实际授权：用户“直接修复”，暂停原Grok实施接力，由Codex修复必要依赖；不提交、不上传。
- 写入状态：已停止

## 实际修复

1. UserPreferencesRepository.update新增可选expectedCurrentPolicy，在同一无await仓库actor操作内fetch当前单例、按现行winner规则比较策略，再apply与save；不再仅凭服务层早先load的快照写入。直接update仍走此同一仓库actor，不能在本实例的比较与保存之间插入另一个actor调用。
2. PreferencesService将expectedCurrentPolicy传到仓库真实提交；服务层load保留为早期拒绝，明确不是最终安全依据。默认update行为兼容，无同步模型/持久值变化。
3. PreferencesServiceTests新增testPolicyChangedAfterServiceCheckCannotBeOverwritten：两种密码目标分别在第二次授权回调中先直接update为noVerification，再尝试旧目标提交；断言拒绝stale_page_request，保留新档。覆盖08独立验证的窗口。

修改文件：

- ApiRelay/ApiRelay/Data/SwiftData/Repositories/UserPreferencesRepository.swift
- ApiRelay/ApiRelay/Business/System/PreferencesService.swift
- ApiRelay/ApiRelayTests/V1/Phase06_Settings/PreferencesServiceTests.swift

仓库文件是本次直接修复的必要依赖，原波次清单未列入它；本次用户直接修复授权下完成该最小依赖修复，明确记录、不伪称原U2-R1精确清单已经包含它。不改仓库其他功能或任何模型结构。

## 实际验证与限制

Codex实际运行PreferencesServiceTests、RevealGateTests、SecuritySettingsPersistTests、AppPrivacyControllerTests、MasterPasswordServiceTests，签名iPhone17 Pro iOS26.5模拟器，重新执行145项，145通过、0失败、0跳过。原始结果：`/tmp/ApiRelayCodexDirectW3Fix.xcresult`，摘要已核实。git diff --check通过。HEAD/main/origin-main/release标签对象保持契约基线，暂存空、单worktree。未处理tools、manifest或远程。

此保证针对当前仓库actor内本机条件提交；不宣称新增CloudKit跨设备事务或全局多进程CAS。三端界面、系统弹窗、双设备同步仍需W6；W5普通入口尚未整改。本次只关闭08所证实的本地检查/保存窗口，不宣布全项目安全完美或最终验收。

## 接力与方法观察

这是执行者自测，不是独立审计。原01—08证据保留；下一份10由Grok只读独立复核，不能让Codex给自己的修复签独立通过。后续入口先按09/10恢复，不误认为09由Grok写，也不重复用08旧失败要求实施同一已修缺口。

方法观察：用户明确要求直接修复后，执行角色应随授权改变，不能为了机械轮次继续消耗用户；必要仓库依赖一次记录，先修本机真实提交并用原反例回归，而非重复增加外部观察点。

下一步负责人：Grok
是否需要用户批准：否；仅独立只读复核，仍需用户调用，不自动执行。
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4D-Grok直接修复后独立检查.md`

直接修复完成，等待独立复核；不是波次独立审计通过。
