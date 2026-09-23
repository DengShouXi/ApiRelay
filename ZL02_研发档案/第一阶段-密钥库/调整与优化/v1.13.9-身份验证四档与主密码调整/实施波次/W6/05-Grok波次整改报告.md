写入状态：已停止

> 2026-09-15 Codex经用户授权修正同类交接状态：依据本报告原文末已停止声明，移除遗留运行标记。仅修报告状态，不改变实施结果或外部编辑器实时状态。

# 阶段4：Grok波次整改报告（U2-W6）

- 阶段：4
- 修订ID：U2
- 计划修订：U2-R1（产品答案不变；本波按 04 第八节 U2-W6 做总回归、构建、人工矩阵准备和事实同步）
- 波次：U2-W6（基于 U2 最终代码的自动证据；关闭旧 W6/02 能在本波关掉的项；人工与 manifest 处置仍阻塞 `06`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2-R1 版 `04` 第八节、`05` 第八节与第十二节 E、`00C`、W5/11、旧 W6/01–03
- 批准来源：W3/07 记录 2026-09-15 用户原文「明确同意 U2-R1 的 04 和 05」。本波未要求重复批准。W5/11 独立结论「波次审计通过，可以进入下一波。」
- 实际授权：用户执行 `提示词/阶段4-Grok执行下一波.md`。W5/11 存在且合法独立通过，故将 W5 视为通过并只实施 U2-W6。不重做 W0/W2/W3/W5；不覆盖 W6/01–03；不创建 `06`；不处理 `tools/`、xcodeproj/manifest、暂存、提交、上传、main/tag
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` 对象 = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree；`git diff --check` 通过

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2 链：W0/08、W2/10、W3/10、W5/11 通过。旧 W6/01 的 358 绿只是旧实现基线，不能证明 U2。
- 本文件为 `实施波次/W6/` 下一个连续奇数报告 `05`，不覆盖 01–03。
- 上一写入者：W5/11 已停止。未读取、未修改 `tools/`。未改 Swift。未打开 `manifest.json` 正文。

## 2. 本波实际文件（均在原 W6 清单 ∩ `00C.allowedModify` 内）

| 文件 | 做什么 |
| --- | --- |
| `ZL01_具体说明/14-项目当前状态.md` | 事实同步：规格已回写、本机代码已改完、正在验收；保留 B2 拆开的手测/Archive 口径 |
| `ZL01_具体说明/04-设计与规格.md` | 同步「代码已改完、正在验收」；宪法版本写 v2.16.0 |
| `ZL02_研发档案/第一阶段-密钥库/00-阶段总览.md` | 索引改为本机代码已改、验收进行中 |
| `ApiRelay/specs/playbooks/v1-key-vault/phases/P13-人工操作指南/06-TestFlight内测.md` | 本机新包才是现行行为；旧 TestFlight 不是 |
| 本文件 | U2 自动证据、三端接线、人工空表、B3 待决 |

未写 `ZL01/13`。未改 `10`（对话索引，不是普通用户状态页）。未改 `BRANCHES.md`（已写本机代码已改、未提交）。未改实现。测试未发现必须回改 W0—W5 的新阻塞。

## 3. 旧 W6/02 B1—B3

| 项 | 本波 | 是否关闭 |
| --- | --- | --- |
| B1 人工证据 | 05 第十二节 E 与旧 05 第八节 1–7 仍无真机/系统弹窗/双设备结果。W6/03 空表未填。本会话不能代测 Face ID / 分栏 / 多窗 / CloudKit | **未关闭**，阻塞 `06` |
| B2 中文状态与闸门 | W6/03 已拆开验收手测与 Archive。本波再去掉「本机代码尚未改完」的过期句，避免用户以为实现还没做 | **关闭**（文案；不表示验收通过） |
| B3 manifest | 只读元数据与 W6/03 一致：`??`、size 163、birth/mtime 2026-09-15 12:36:03、从未入库、`00C` 禁止 `xcodeproj/`。用户尚未三选一。未读正文、未删、未暂存 | **未关闭** |

工作流检查器退出码 4（预期红，不得标通过）：

```text
不在允许范围的差异:
ZL00_项目总控/04-双AI协作与独立审计.md
ZL00_项目总控/自动化/check_multi_ai_workflow.py
ZL00_项目总控/自动化/task-contract.template.json
ZL00_项目总控/自动化/classify_small_fix.py
ZL00_项目总控/自动化/test_classify_small_fix.py
ApiRelay/ApiRelay.xcodeproj/xcshareddata/xcodecloud/manifest.json
…/提示词/阶段4D-Grok直接修复后独立检查.md
…/提示词/阶段4F-Grok集中修复独立复核.md
```

ZL00 前缀本任务禁止处理。4D/4F 是已授权角色覆盖入口，扩 `00C` 须回阶段 3。本波不扩白名单、不 `git add`。

## 4. 自动证据（U2 最终代码，不是旧 358）

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
git diff --check：退出 0
```

共享 scheme 全量测试：

```text
xcodebuild test -scheme ApiRelay
  -destination 'platform=iOS Simulator,id=3139387C-65A0-41FF-9713-9E1294CDC55C'
  -derivedDataPath /tmp/ApiRelayAgentW6U2-ios-test
  -resultBundlePath /tmp/ApiRelayU2W6-05.xcresult
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
```

独立读取摘要：iPhone 17 Pro / iOS 26.5 模拟器，**425 passed / 0 failed / 0 skipped**，`** TEST SUCCEEDED **`。日志 `/tmp/ApiRelayU2W6-05-ios-test.log`。该次同时覆盖 **iOS 模拟器 Debug** 编译。旧 358 不作新方案证明。

可用构建（独立 DerivedData）：

| 配置 | DerivedData | 结果 | 日志 |
| --- | --- | --- | --- |
| iOS 模拟器 Debug | `/tmp/ApiRelayAgentW6U2-ios-test` | 全量测试覆盖 | `/tmp/ApiRelayU2W6-05-ios-test.log` |
| iOS 模拟器 Release | `/tmp/ApiRelayAgentW6U2-ios-release` | `** BUILD SUCCEEDED **` | `/tmp/ApiRelayU2W6-05-ios-release.log` |
| Mac Catalyst Debug | `/tmp/ApiRelayAgentW6U2-mac-debug` | `** BUILD SUCCEEDED **`（未带 `CODE_SIGN_IDENTITY="-"`） | `/tmp/ApiRelayU2W6-05-mac-debug.log` |
| Mac Catalyst Release | `/tmp/ApiRelayAgentW6U2-mac-release` | 同上 | `/tmp/ApiRelayU2W6-05-mac-release.log` |

Mac Catalyst **只证明能编过**，不是电脑上手测，也不是已运行的产品窗口。

敏感材料：生产无真实 API Key / 硬编码口令；`print` 仅 CloudKit 引导与 Diagnostics。未知 `RevealPolicy` rawValue fail-closed 到 `.biometricOrPasscode`，不回落 `.noVerification`。`biometricOnly` 只在解码层。`confirmMandatory` 仍只用于设备主人 / 设密 / 恢复。

## 5. 三端接线（共享代码 ≠ 三端通过）

| 端 | 生产入口 | 本波自动结果 | 未验证 |
| --- | --- | --- | --- |
| iPhone | 锁屏 `AppLockCoverView`/`AppPrivacyController`；保管库 `VaultHomeView`/`ViewModel`/`KeyDetailView`；备份 `BackupSettingsViews`；设置 `SettingsView` | 模拟器 425 项绿、Debug/Release 构建 | 真机 Face ID、系统弹窗、导航手测 |
| iPad | 同一套 SwiftUI；另有分栏/关详情清授权 | 未单独跑 iPad 模拟器（与 iPhone 同测试靶，算法不重跑） | 分栏、关详情后再复制 |
| Mac Catalyst | 同一套入口；设备验证档用 Mac 登录密码；组合档取消不得弹登录密码 | Debug/Release **构建**成功 | 未启动 App；Touch ID 有/无、快捷键、多窗 |

## 6. 实测问题 → 入口 → 证据 → 未验证

| 实测问题 | 生产入口 | 修复所在（前波，本波未改 Swift） | 自动证据 | 未验证 |
| --- | --- | --- | --- | --- |
| 两种档进同一应用密码页 | `SettingsView` 选档/管理 | U2-W3 | `AppPrivacyControllerTests` 等 | 三端导航手测 |
| 未设立即设密、已设不强迫改 | `createAppPasswordMaterialThenPersist` | U2-W3 | RevealGate / Preferences 队列测试 | 真机设备主人弹窗 |
| 普通入口不设密 | Vault/备份/锁/设置 | U2-W5 | `testOrdinary*`、`testMasterOnly*`、`testBackupMasterOnly*`、`testCombinationLockSetupDoesNotWritePassword` | 三端点「使用应用密码」 |
| 缺材料独立恢复不重试原业务 | `recoverFromLostMasterPassword` + 普通入口先丢待办 | U2-W3/W5 | `testOrdinaryMissingMaterialIndependentRecoveryDoesNotRetryDelete`；恢复锁态复用 W3 | 锁屏/设置全流程手测 |
| 组合档取消不回落设备密码 | `CurrentRevealPolicyAuth` | U2-W2/W5 | `testCombinationConfirmWithoutPasswordUsesBiometricsOnce` 等 | 真机取消 Face ID |
| 取用复用七种失效 | `VaultHomeViewModel` 生产接缝 | 原 W5 + U2-W5 定向回归 | `RevealGateCoordinatorTests` reuse* | iPad 分栏、Mac 多窗 |
| 双设备无本机材料 | 材料本机 Keychain + 锁屏恢复 | U2-W2/W3 | 单测隔离，不是 CloudKit | 双真机同步 |

## 7. 人工矩阵（结果全空 = 未验证）

谁做、测哪个包、怎么记：沿用 W6/03 §3.1。必须是当前工作区 Xcode Run 的本机新包。下表覆盖 `05` 第八节 1–7 与第十二节 E 必填行。实际/日期未填即未验证。缺一格不得生成 `06`。

| # | 行（05 E / 第八节） | iPhone | iPad | Mac Catalyst |
| --- | --- | --- | --- | --- |
| E1 | 已设/未设点两种档均进同页 | 未验证 | 未验证 | 未验证 |
| E2 | 已设保留密码继续 | 未验证 | 未验证 | 未验证 |
| E3 | 取消页面不切档 | 未验证 | 未验证 | 未验证 |
| E4 | 切出隐藏、切回保留密码 | 未验证 | 未验证 | 未验证 |
| E5 | 组合档立即设密且目标正确 | 未验证 | 未验证 | 未验证 |
| E6 | 应用密码档立即设密 | 未验证 | 未验证 | 未验证 |
| E7 | 第三档能切换 / 缺材料可恢复 | 未验证 | 未验证 | 未验证 |
| E8 | 四档管理行显示与刷新 | 未验证 | 未验证 | 未验证 |
| E9 | 首次设置设备主人 | 未验证 | 未验证 | 未验证 |
| E10 | 旧密码修改 | 未验证 | 未验证 | 未验证 |
| E11 | 普通入口不设密 | 未验证 | 未验证 | 未验证 |
| E12 | 取消/保存失败不误切档 | 未验证 | 未验证 | 未验证 |
| 8.1 | 设备验证成功/取消 | 未验证 | 未验证 | 未验证 |
| 8.3 | 组合档取消不回落设备密码 | 未验证 | 未验证 | 未验证 |
| 8.4–8.5 | 不验证不上锁；改回有验证后自动锁再生效 | 未验证 | 未验证 | 未验证 |
| 8.5 | 同详情查看→复制；关详情/换 key/离前台 | 未验证 | 未验证 | 未验证 |
| 8.6 | 双设备 A 有材料 B 无 | 未验证（需两台真机同一 iCloud） | — | — |
| 8.7 | 备份与永久删除顺序 | 未验证 | 未验证 | 未验证 |
| UI | VoiceOver / Dynamic Type / 布局 | 未验证 | 未验证 | 未验证 |

无生物硬件的子项不得整行标不适用；该端须测设备密码或已配置应用密码替代路径，结果仍待用户填。

## 8. 收尾四问

1. **外部资源：** 本波未新写 Keychain / SwiftData / CloudKit / UserDefaults / App Group。全量测试仍用 `KeychainStore.makeForTests()` 与内存容器。未打开 App 组。manifest / `tools/` 未读正文、未纳入。
2. **失败路径：** 真机若仍是旧四档/旧默认，说明装的是旧 TestFlight，不能当本机新包通过。B1/B3 未关则不能验收、不能汇总 `06`、不能上传。提交/Archive 仍须另句授权。设置页仅应用密码档降低安全仍可能先出口令框（W5/11 残差，0 设密）；本波测试未把它变成失败用例，不在此改 Swift。
3. **接缝：** 未新增 protocol。
4. **文件粒度：** `VaultHomeView.swift` 等仍超过 400 行，本波不拆。`14` 远低于 400 行。

## 9. 未验证 / 停止点

- 人工矩阵与双设备：未验证，**阻塞 `06`、阶段 4B、5、7、8**。
- B3：用户未选择保留未跟踪 / 自行删除 / 回阶段 3。检查器退出码 4 仍在。
- 英文 `vault.masterPassword.title` 仍为 Enter Master Password；中文已是应用密码。不在本波扩整改。
- 不得用 425 绿或 Catalyst 构建冒充三端运行通过。不得预写上传成功。

## 10. 方法观察

U2 把实现做完之后，中文状态页若仍写「代码尚未改完」，会比「手测未做」更误导。W6 事实同步要改的是普通用户能核对的实现/验收进度，不能把内部波次号写进 `14`。检查器红结果必须原样记录；扩白名单不是本波权限。

下一步负责人：Codex
是否需要用户批准：否（人工表与 B3 仍需用户参与，但不阻止 4A 核对自动证据；通过 4A 也不等于可进 4B）
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
