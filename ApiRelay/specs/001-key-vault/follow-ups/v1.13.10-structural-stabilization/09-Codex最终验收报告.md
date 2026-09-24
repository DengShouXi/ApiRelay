# v1.13.10 阶段 7 · 独立最终验收报告

方法版本：MAIC-1.3.1  
阶段：7  
时间：2026-09-24（中国标准时间）  
分支：`v1.13.10`  
起始 HEAD：`25fe006896a816475e269e155530c1464cc19304`  
实施者：Codex 阶段 6 执行角色  
验收者：Codex 独立审计代理（非阶段 6 实施者）  
输入：本工作包 00、00B、00C、00D、00E、03、04、06、07、08、阶段 7 提示词、ZL00/04、实际 Git 差异和四份原始 xcresult。  
授权边界：仅独立验收并写本报告；不修改产品代码、契约或原工作树，不提交、不上传、不发布。

## 阶段 5 四项阻塞的复验

1. **W4 ownership：已收口。** `SettingsPreferencesStore` 以 committed、draft、revision 管理同一偏好展示来源，旧 reload 不得覆盖新草稿；`SettingsPendingActionState` 使安全降级和清除数据的待认证动作互斥。`VaultTrashPresentationState` 统一父视图的回收站展示/勾选/可见集，批量动作仅使用已勾选与当前可见项交集；子视图内筛选结果是派生数据。`StateOwnershipTests` 对上述旧读取、互斥与隐藏项边界均有通过的断言。生命周期数据流经平台 scene/窗口焦点信号进入 `AppPrivacyController`，由 `WindowPrivacyReducer` 派生窗口遮罩；`AppLockSession` 仍是锁定真相源，`SessionLockBox` 仅由 `AppPrivacyController.session` 的初始化和 `didSet` 镜像更新，业务接口 `SessionLockQuerying` 只读。后台轮次、认证抑制等是事件证据，并非第二个锁态权威；为保持冻结的 iPad 快返/Mac 认证时序，未机械迁移该部分。`AppPrivacyControllerTests` 与最终全套结果覆盖其边界。
2. **桌面 UI：已取得真实运行证据。** 原生 macOS 与 Mac Catalyst 各有 3 个实际 UI 断言通过、0 失败、0 跳过、0 运行警告；不是以构建成功代替运行。Mac 遮罩的宿主同级视图修正已包含在结果中，未申请系统“控制电脑”权限。
3. **错误应用密码回滚：已补真实 UI 用例。** `testWrongAppPasswordKeepsPolicyAndAllowsRetryOnCurrentPage` 输入错误密码后断言错误、原策略仍选中、当前页可重试，再以正确 fixture 密码完成切换；最终 iPhone/iPad 结果包含该用例，iPad 原始 tests 节点为 `Passed`。
4. **安全偏好回调：顺序与旧结果隔离已验证。** `SecurityPreferenceCommit` 在串行持久化回调后依次向主队列投递通知，降低安全级别仍须落盘成功后才改变展示状态。通知携带 request/draft revision；设置页拒绝旧结果触发的 reload。`StateOwnershipTests` 验证连续成功→失败的通知顺序、主线程交付以及旧通知不覆盖新请求/草稿；密码失败 UI 用例验证页面可继续操作。

## 原始测试与安全证据

独立使用 `xcrun xcresulttool get test-results summary` 读取下列原始结果，四份均为 `Passed`，无失败、跳过或运行警告；新增 fixture 与遮罩修正文件的修改时间早于相应最终结果。

| 平台／范围 | 通过数 | 原始 xcresult |
| --- | ---: | --- |
| iPhone 16 iOS Simulator 全套 | 617 | `/private/tmp/ApiRelay-v11310-phase6-sealed-iphone-all.xcresult` |
| 原生 macOS UI | 3 | `/private/tmp/ApiRelay-v11310-phase6-mac-ui-coverfix.xcresult` |
| Mac Catalyst UI | 3 | `/private/tmp/ApiRelay-v11310-phase6-final-catalyst-ui.xcresult` |
| 最终 iPad (A16)／iPadOS 26.5 Simulator UI | 4 | `/private/tmp/ApiRelay-v11310-phase6-sealed-ipad-ui.xcresult` |

`ApiRelay.entitlements`、`Schema.swift`、`KeychainStore.swift` 的 SHA-256 分别为 `8c49887c42f110a6b6f92c1f85ba1d66fbb53e04df295a6a7d91e8394532a3c0`、`0a1537ab4296c9f17f125d9bf98147912262b3c75ef25ecefb11a679ba18c3a8`、`0693a04fbfca06f874f300dda394c854716206e8f556b0f398e39aa60795b6f7`，与 04 基线逐项一致。KeyVault actor、持久 WAL/提交路径、数据模型与 entitlements 无本工作包差异；DEBUG UI fixture 使用内存假服务，未关闭遮罩或解锁提示，不接触真实密钥/CloudKit。结构拆分及 AppKit 遮罩修正经上述回归覆盖，未发现需阻止本阶段的产品语义漂移。

## 范围、隔离与裁决边界

`git diff --check` 通过，暂存区为空；当前工作树仍为 `v1.13.10`、原工作树仍为 `v1.13.9`，两者 HEAD 均为上述基线。独立运行 v1.13.10 真实检查器退出 0，报告前路由为阶段 7；当前差异与新增文件均在契约允许范围。

原 `v1.13.9` 真实检查器**仍退出 4**，原因是其契约外存在本 `v1.13.10` worktree；这仍是原包阻塞，绝不记为通过。`00D` 明示旧只读指纹 `838414ac8e8eb18dc8bc878ef48624881ad69684d541f5b3e934a262e3c2b809` 已失效且历史期间逐文件变化不能完全归因。独立解压 `00E` 并与当前原树 `git status --porcelain=v1 -z -uall` 和 1183 个逐文件内容/类型/权限比对一致，确认新的只读指纹为 `f65cbd67583845544e575820540a90a8390db14257faff9b4a2a6d1ad445ecbd`；此结论仅保护**新快照起向前**的隔离，不追认旧历史。原树未被本次验收修改、合并、清理或提交。

本结论是 v1.13.10 本地结构治理阶段的验收，不代表 iPad/iPhone 真机生物识别、系统设备密码、实际 App Switcher 或跨设备同步已经由模拟器自动测试证明。下一阶段提交/上传须由用户另行明确授权，且不得把本报告或检查器路由解释为授权。

方法观察：已批准的受控重基线把旧历史限制与向前隔离分开，原包退出 4 仍如实保留；未发现需要在本阶段再次修改通用方法的阻塞。

写入状态：已停止

验收通过，可以在用户明确授权后提交并上传 v1.13.10。
