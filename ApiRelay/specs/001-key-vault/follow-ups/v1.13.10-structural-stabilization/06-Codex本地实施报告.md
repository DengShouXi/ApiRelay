# v1.13.10 阶段 4 · 本地实施报告

方法版本：MAIC-1.3.1  
阶段：4  
实施 worktree：`/Users/xitongzhili/.codex/worktrees/v1-13-10-structural/E02_ApiRelay_Github`  
分支：`v1.13.10`  
基线 HEAD：`25fe006896a816475e269e155530c1464cc19304`  
时间：2026-09-24

## 实际改动

- W1：新增真正的 Xcode UI-test target、共享 scheme、固定 DEBUG-only 测试场景与内存 fixture；测试场景不访问生产 Keychain、CloudKit 或用户数据，并保留真实生命周期观察。新增设置页密码策略连续切换、锁定/解锁/重启、iPhone/iPad 立即后台锁定的 UI 断言，以及稳定的 accessibility ID。新增结构与状态来源单测。
- W2：将 `VaultHomeView` 的重复提示、回收站视图、实体表单拆入独立文件；将 `SettingsView` 的付费页与清除数据流程拆出。密码设置页面因既有源码形态测试依赖原位置而保留，不修改旧测试。视图文案、导航和 modifier 顺序未主动变更。
- W3：将 `SessionLockQuerying` 中独立的安全偏好提交、显式认证、应用密码策略及设置流程拆出；将 `SecureBackupService` 顶层模型/协议拆出；将 `AppPrivacyController` 的平台快照遮挡视图拆出。未改变 KeyVault、SecureBackup 的 actor、WAL、await 或最终提交顺序。修复安全偏好异步持久化完成后从后台线程发布 SwiftUI 通知的问题，改为主 actor 发布。
- W4：删除密码策略页面重复的 `highlightedPolicy` 本地状态，以 `effectiveCurrentPolicy` 作为显示与认证的单一来源；新增状态来源的回归断言。计划中其他 ownership 项（设置 committed/draft、互斥 pending action、Vault 派生/回收站、生命周期 reducer、session writer capability）尚未逐项完成或证明可以安全合并，不能声称 W4 已全部达成。已单一的 gate/coordinator/clipboard 未重写。
- W5：执行签名单测、三端构建、iPhone/iPad UI 测试、敏感标识及契约检查。同步只更新阶段边界说明，未实现同步迁移；UI 重设计不在本阶段。

## 验证结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 签名全量单测 | 608 通过，0 失败、0 跳过、无运行期警告 | `/private/tmp/ApiRelay-v11310-signed-unit-final.xcresult` |
| iPhone Simulator UI | 3 通过，0 失败、0 跳过、无运行期警告 | `/private/tmp/ApiRelay-v11310-iphone-ui-final.xcresult` |
| iPadOS 26.5 Simulator UI | 3 通过，0 失败、0 跳过、无运行期警告 | `/private/tmp/ApiRelay-v11310-ipad-ui-final.xcresult` |
| iOS、原生 macOS、Mac Catalyst 签名 build-for-testing | 均通过 | Xcode 构建输出 |
| macOS/Catalyst UI | **未执行到应用断言**；宿主 UI runner 在启用自动化模式时超时 | `/private/tmp/ApiRelay-v11310-mac-ui.xcresult`、`/private/tmp/ApiRelay-v11310-catalyst-ui.xcresult` |
| 敏感文件 SHA-256 | entitlements、SwiftData schema、KeychainStore 与 `04-不可逆标识基线.md` 一致 | 本地 `shasum -a 256` |
| 范围/格式 | 阶段 4 契约检查有效；`git diff --check` 通过 | 本地检查 |

曾在无签名测试配置下出现 Keychain 材料不可读，签名后代表性测试与上述全量套件通过；不能将无签名环境结果误报为产品失败。iPadOS 18 的一次旧运行在模拟器诊断时挂起，最终 iPadOS 26.5 运行完整通过。

## 未完成与闸门

1. Mac UI 自动化尚缺宿主系统权限/runner 初始化验证。已向用户单独请求是否允许授予“辅助功能”控制电脑权限；在明确同意之前不修改该系统权限。三端构建通过不等于三端 UI 已通过。
2. W4 尚未全部实现。阶段 5 独立审计须判定剩余项是否为阻塞；若是，按阶段 6 整改，不能直接宣称 v1.13.10 完工。
3. 没有提交、推送、上传、合并、修改生产持久格式或将 `v1.14` 同步实现混入本分支。原 `v1.13.9` 脏工作树未写入。

写入状态：已停止
