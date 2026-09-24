# v1.13.10 阶段 6 · 阻塞整改报告

方法版本：MAIC-1.3.1  
阶段：6  
时间：2026-09-24（中国标准时间）  
分支：`v1.13.10`  
起始 HEAD：`25fe006896a816475e269e155530c1464cc19304`  
实施者：Codex 阶段 6 执行角色  
输入：本工作包 00、00B、00C、00D、00E、03、04、06、07、阶段 6 提示词；实际 Git 差异与下列原始 xcresult  
授权：用户要求实现受控重基线并继续现有阶段 6；不含提交、上传、购买、同步或发布。

## 阶段 5 四项阻塞的处理

1. **W4 状态归属。** 设置页已以 `SettingsPreferencesStore` 维护唯一的 committed snapshot、乐观 draft 与 reload revision；旧异步读取不能覆盖新编辑。`SettingsPendingActionState` 将安全降级和清除数据的待认证动作合为互斥状态。回收站由 `VaultTrashPresentationState` 统一维护勾选、当前可见集及空态，批量操作只取“已勾选 ∩ 当前可见”。对应 `StateOwnershipTests` 覆盖旧读取覆盖新草稿、互斥敏感动作及隐藏条目不得进入批量操作。

   生命周期和 session 锁没有新造第二套权威：平台 scene/宿主焦点信号进入 `AppPrivacyController`，`WindowPrivacyReducer` 从窗口快照派生进程 presence 与各窗遮罩；`AppLockSession` 是“是否锁定”的唯一状态源，`AppPrivacyController.session` 更新时同步镜像到 `SessionLockBox`。`setLocked(` 的生产调用点仅为 `AppPrivacyController` 的启动初始化与 `session` didSet；业务服务构造后只持有 `any SessionLockQuerying`，不能经该接口设置锁态。Controller 内的后台轮次、焦点与认证抑制字段是不同生命周期事件的临时证据，不是另一份 `isSessionLocked`。因此按阶段 5 允许的“已是单一权威则给出数据流与不迁移理由”处理此项；为了纯结构阶段不改变 iPad 快返和 Mac 系统认证时序，没有把这些证据机械迁到新 reducer。既有 `AppPrivacyControllerTests` 覆盖快速 Home、Stage Manager/多窗、Mac 失焦、系统认证和遮罩边界；最终全量结果见下。

2. **Mac/Catalyst 真实 UI 断言。** 原生 macOS 的 UI runner 在关闭并行运行后完成 3/3；Catalyst 完成 3/3。两份结果均 0 失败、0 跳过、无运行警告。Mac 快照遮罩放在宿主内容上方的同级视图，修正原先子视图约束警告；未申请“控制电脑”权限。构建成功不作为 UI 通过的替代证据。

3. **错误应用密码回滚。** `SecuritySettingsUITests.testWrongAppPasswordKeepsPolicyAndAllowsRetryOnCurrentPage` 在真实 UI 输入错误密码，断言显示错误、原应用验证策略仍被选中、页面保持可重试；再输入正确 fixture 密码并断言当前页切到设备验证。该用例随最终 iPhone 和 iPad UI 结果运行；桌面 UI 套件也实际运行。

4. **安全偏好通知顺序。** `SecurityPreferenceCommit` 从生产的串行写入链回调中依次 `DispatchQueue.main.async` 通知，保持主线程交付及回调入队顺序；降低安全等级在 persist 成功前不更新内存。`SecurityPreferenceNotificationContext` 随请求／草稿 revision 传播，设置页忽略不属于当前编辑的旧成功或失败通知。`StateOwnershipTests` 覆盖“成功后失败”的完成顺序、主线程交付和旧通知不得覆盖新请求／草稿；错误密码 UI 用例覆盖失败后的可重试状态。

## 受控只读重基线

用户批准将原 `v1.13.9` 检查器退出 4 保留为**原包阻塞**，并接受“旧快照期间逐文件变化无法完全回溯”的明示限制，按新现状建立向前有效的只读基线。旧指纹、新指纹、1183 条逐文件清单及独立隔离复核见 [00D-受控重基线记录.md](./00D-受控重基线记录.md) 与 [00E-原工作树只读清单.json.gz](./00E-原工作树只读清单.json.gz)。独立隔离角色重新解压逐条比对原树，确认清单完全一致、`v1.13.10` 冻结治理文件和保护路径未漂移，结论仅为**向前隔离通过**。此处不声称旧历史已归因，也没有改原 `v1.13.9` 契约或把其退出 4 写成通过。原树购买界面文件、构建号 11 和其它 Xcode 差异仍原地保留，未合并、清理或提交。

## 原始测试与最终核对

| 平台／范围 | 结果 | 原始结果 |
| --- | --- | --- |
| iPhone 模拟器全套 | 617 通过，0 失败，0 跳过，0 运行警告 | `/private/tmp/ApiRelay-v11310-phase6-sealed-iphone-all.xcresult` |
| 原生 macOS UI | 3 通过，0 失败，0 跳过，0 运行警告 | `/private/tmp/ApiRelay-v11310-phase6-mac-ui-coverfix.xcresult` |
| Mac Catalyst UI | 3 通过，0 失败，0 跳过，0 运行警告 | `/private/tmp/ApiRelay-v11310-phase6-final-catalyst-ui.xcresult` |
| 最终 fixture 的 iPad (A16)／iPadOS 26.5 模拟器 UI | 4 通过，0 失败，0 跳过，0 运行警告 | `/private/tmp/ApiRelay-v11310-phase6-sealed-ipad-ui.xcresult` |

四份结果均由 `xcresulttool get test-results summary` 重新读取，`result=Passed`。最终 fixture 与 AppKit 遮罩修复文件的修改时间均早于上述四份结果；本轮 iPad 运行使用 `-parallel-testing-enabled NO` 且 `xcodebuild` 退出 0。以上是模拟器／桌面自动测试，不冒充 iPad 真机的生物识别验收。

`v1.13.10` 工作包检查器在补测后退出 0，指向当前阶段 6；原 `v1.13.9` 工作包检查器仍退出 4（契约外 worktree），原包继续阻塞。`git diff --check` 通过、暂存区为空、两树仍分别在 `v1.13.10`／`v1.13.9` 且 HEAD 同为上述基线。`ApiRelay.entitlements`、`Schema.swift`、`KeychainStore.swift` SHA-256 分别为 `8c49887c42f110a6b6f92c1f85ba1d66fbb53e04df295a6a7d91e8394532a3c0`、`0a1537ab4296c9f17f125d9bf98147912262b3c75ef25ecefb11a679ba18c3a8`、`0693a04fbfca06f874f300dda394c854716206e8f556b0f398e39aa60795b6f7`，与 04 基线一致。

本报告是执行者的整改和自测证据，**不是阶段 7 独立验收结论**。下一负责人：Codex 独立审计角色；下一提示词：[阶段7-Codex最终验收.md](./提示词/阶段7-Codex最终验收.md)。不提交、不推送、不上传 TestFlight、不申请 App 审核。

方法观察：受控新基线把“旧历史不可逐项回溯”与“从当前清单起可检测漂移”分开记录，避免用检查器退出 0 追认旧区间；未发现需再次修改通用方法的新阻塞。

写入状态：已停止
