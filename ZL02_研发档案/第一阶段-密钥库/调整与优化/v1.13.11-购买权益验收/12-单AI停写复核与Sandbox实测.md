# v1.13.11 单 AI 停写复核与 Sandbox 实测

## 2026-10-09 Mac 交易环境复核与退款再次受阻（本轮最新）

分支仍为 `v1.13.11`，HEAD 仍为 `0f00255bc380eab8d5ff80c8e6145e5b28641172`。本轮没有提交、推送或新建分支；测试前将 Mac App 的 `Data` 目录备份到 `/private/tmp/ApiRelay-v11311-mac-container-before-refund-fv5rHi/Data`（约 1.7 MB，不含系统钥匙串），没有清除容器、交易或 Sandbox 购买历史。

- 直接启动先前签名的 Mac Debug 包时，设置页显示免费，恢复购买返回“未找到可恢复的购买”，购买入口报 `transaction_not_eligible`。临时只读诊断日志确认当时 `Transaction.currentEntitlements` 返回一笔**未撤销 `.xcode` 本地测试交易**，`AppTransaction` 环境也为 `.xcode`；普通 App 的授权规则按设计拒绝此类交易。因此这次免费态和错误不是 Apple 已退款，也不是对先前真实 Sandbox 付款的反证。
- 将 Xcode 目标切为原生 **My Mac**，核对 Run → Options → StoreKit Configuration 为 **None** 后重新 Run 同一候选源码。Xcode Console 此时多次确认 `currentEntitlements count=1`，交易和 `AppTransaction` 环境均为 **Sandbox**，目标产品匹配、`revocationDate == nil`；设置页读取 `settings.entitlement.state.owned = 已解锁`。这为 Mac 当前真实 Sandbox 权益补上直接环境证据。Apple 官方说明将 Run 配置设为 None 后会使用 App Store Connect 数据，而非本地 StoreKit 文件；参考 [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)。
- 停止调试后直接启动先前已验签的一次性退款探针，设置页仍为“已解锁”，并允许打开 `Sandbox 退款验收`。Apple 原生退款表单加载后再次显示“无法连接”；准确点击“重试”一次，仍为“无法连接”。关闭后 App 只得到 `userCancelled`，**没有提交退款**，也没有撤权或撤权后额度证据。探针已退出；源码中的两条临时 `#if DEBUG` 环境日志已撤回，正式候选源码不保留退款入口或该日志。
- 工作包检查器复查退出 **0**，`git diff --check` 退出 0，暂存区为空，HEAD 未移动；Xcode 本次没有留下新的 `xcodecloud/manifest.json`。检查器只表示范围与路由有效，**不授予阶段 7、提交或上传权限**。

执行结论与交接：真实购买、Mac/iPhone/iPad 当前权益和恢复有证据，自动 StoreKit 退款/撤权及免费额度回归有测试证据；但 Apple 原生真实 Sandbox 退款表单在 iPhone、Mac 均持续无法连接，实际批准退款、拒绝退款、撤权和跨设备撤权仍未验。Apple Developer Support 案例 `102975484910` 继续跟进。服务恢复后应在真实 `.sandbox` 未撤销交易上先测拒绝（`Other` + `DECLINE`，权益应保持），再准备可重复购买的测试账号或交易，测批准退款、`revocationDate`、三台设备撤权和三把免费额度；[Apple 退款测试文档](https://developer.apple.com/documentation/storekit/testing-refund-requests)说明这两类结果。不得用清除购买历史或 Xcode 本地退款冒充。若 Apple 服务仍不可用，保留本工作包为“未完成/外部阻塞”，由用户另行决定是否修改正式验收范围；在现行闸门下不得宣称阶段 7 通过、提交上传或开下一产品热修分支。

随后用户明确选择“同意延期退款验收，修订计划并重新验收”。据此[最终计划顶部限定修订](./04-最终计划.md)把上述真实退款条目保留为**未通过的对外发布前验收**，不再把它作为本轮 `v1.13.11` 开发分支阶段 7 的单独否决项。此决定不自动使阶段 7 通过，也不授权提交、上传或公开发布；上段“若服务仍不可用即保持未完成”的判断是**用户作出此范围决定之前**的状态。

方法观察：同一 bundle ID 的直接启动 Debug 包可能碰到先前 `.xcode` 本地交易；本轮增加了 Run 配置与交易环境的双证据核对，避免将本地假交易错误解释为真实 Sandbox 撤权。

## 2026-10-09 真实 Sandbox 补验：购买、取消、恢复通过，退款仍阻塞

本轮继续使用独立 `v1.13.11 @ 0f00255bc380eab8d5ff80c8e6145e5b28641172` 及现有未提交购买差异。用户本人完成系统解锁、Sandbox 登录和需要凭据的系统交互；账号、密码未交给 AI。没有 commit、push、分支移动、tag、Archive、TestFlight、送审或关账。

### 2026-10-09 实体 iPad 续验：跨设备自动恢复与手动恢复

- 实体 iPad Pro 13-inch (M4) / iPadOS 26.7.1 原装 `1.0.1(9)`；用户已解锁设备。先前旧包点“恢复购买”出现 `[Environment: Xcode]` 付款面板，立即取消，因此那次不能计为 Sandbox 恢复。本轮只使用独立 `v1.13.11` 工程，Xcode Run 的 StoreKit Configuration 已核对为 **None**。
- 用户在获知覆盖安装可能丢失本机容器数据、备份不含 Keychain 后，明确同意继续。先复制当前 App 容器到 `/private/tmp/ApiRelay-ipad-container-backup-20261009-piGH1U`（约 57 MB），再以 Xcode Run 保留数据覆盖安装开发签名候选包 `1.0.1(24)`；设备 App 列表复核构建号为 24。该备份不是整机或钥匙串备份。
- 停止 Xcode 调试后通过设备自动化独立启动 App，设置页在**未点手动恢复前**显示“已解锁”。随后由自动化准确点击“恢复购买”；Apple 弹出真实账户密码面板，用户本人输入 Sandbox 密码并确认，返回设置页同时显示“已解锁”和“已恢复购买”（画面 `/private/tmp/v11311-ipad-build24-restore-result.png`）。这是当前候选包的实体 iPad 自动权益呈现与显式恢复反馈证据；由于操作前已购，不冒充“免费→已购”恢复，也未在本次构建直接打印 `.sandbox` 交易环境。较早同一 iPad 在 StoreKit Configuration=None 条件下已记录与 iPhone 同购买时间的已验签 `.sandbox` 交易，作为环境旁证，不能替代本次独立交易日志。
- 覆盖安装和恢复后原有密钥列表仍可见；两条“本机暂无明文”在安装前已存在，不归因于本次覆盖。未打开密钥明文、未新增或删除密钥。Xcode 工程内为 GUI Run 临时设的 Debug 构建号 `24` 已恢复为 `9`，`project.pbxproj` 无工作树差异。
- Xcode Run 再次生成契约外 `xcshareddata/xcodecloud/manifest.json`；其 SHA-256 与先前保存的实施树副本完全相同，故仅移除这次在实施树生成的副本，保留 `/private/tmp/ApiRelay-v11311-out-of-scope-20261009/implementation-xcodecloud-manifest.json`。随后工作包检查器退出 **0**、暂存区为空、无范围或写入冲突；`git diff --check` 退出 0。检查器只路由到阶段 7，不授予独立验收、提交或上传权限。
- 当前账号已购，设置页升级行是不可进入付款页的“已解锁”；源码 `PaywallView` 在 `isOwned` 时也不渲染价格，故**不能声称这台实体 iPad 显示了 `$4.99` 付款报价**。另从 App Store Connect 的 `Unlimited Keys` 当前价格表直接读到美国区 `$4.99`，本地 `ApiRelay.storekit` 与 DEBUG 假商店也为 `$4.99`。各国家/地区按 Apple 价格矩阵折算，并非所有货币都显示字面 `$4.99`。

### 2026-10-09 后续阻塞整改

- AppIcon 仅取消暂存；实施树契约外副本和 Xcode Cloud manifest 已备份到 `/private/tmp/ApiRelay-v11311-out-of-scope-20261009/` 后移出，根工作树原内容保留。根只读树按实际分支、HEAD 与文件内容重新冻结后，工作包检查器已由退出 4 改为退出 **0**，暂存区为空、保护 refs 一致、无范围冲突。
- 三份旧文档已统一为“StoreKit 权威交易是唯一授权事实；`EntitlementSnapshot` 只观测、不授权”，不再保留“离线兜底放行”的相反实施指令。
- iPad（第 10 代）/ iPadOS 18 购买 UI **11/11 通过**，包含 `$4.99` 断言。实体 iPad 已在不重装、不清容器前提下打开既有 App，但停在隐私锁 `vault.lock.cover`；尚未安装本轮候选包或完成人工解锁，因此真实平板跨设备自动恢复和手动恢复仍未验。Catalyst 历史异常用例连续 **20/20 通过**；新跑完整单元先因 3 个用例误用共享 Xcode StoreKit 已购状态而得 **637/640**，隔离测试边界后定向 **3/3**、完整 **640/640** 通过。失败与通过证据均保留在本工作包 `证据/`。
- 历史首次 Catalyst 宿主提前退出仍无可证明根因，本轮只能证明未复现。用户明确表示确实不能解决的项目可暂按现状使用、后续出问题再改；因此登记为接受残余风险，不冒称已定位修复。
- iPhone 替换重装造成的旧本机数据不能由代码安全恢复，只能用可信备份或重新录入。用户选择暂按现状使用；这不等于数据已恢复。Apple 退款页“无法连接”仍是外部阻塞，真实退款/撤权与撤权后额度证据继续缺失。

### 价格统一为 `$4.99`

- 用户登录 App Store Connect 后，只读核对唯一的非消耗型项目 `com.apirelay.iap.unlimited_keys`（内部 ID `6800102975`）：美国基准地区的手动价格为 `$4.99`，无开始或结束日期。后台原本已是 `$4.99`，本轮没有执行后台价格写入。
- 本地 `ApiRelay.storekit` 原本已配置 `4.99`；发现 DEBUG 假商店 `FakeStoreKitClient` 仍返回 `$0.99`，已改为 `$4.99`。这解释了至少一条本地测试/预览路径为何会显示旧价，但不能据此断言每次真实 Sandbox 的旧价都来自同一来源。
- `PurchaseEntitlementUITests.testCancellationKeepsPurchasePageUsable` 新增 `$4.99` 显示断言。iPhone 17 Pro / iOS 27 模拟器针对性回归 **1/1 通过**、0 失败，结果包 `/private/tmp/ApiRelay-v11311-price-499-20261009.xcresult`。
- `rg` 在 `ApiRelay/` 内已找不到 `$0.99` / `0.99` 价格残留；当前本地假商店、StoreKit 测试配置与 App Store Connect 均为 `$4.99`。App Store Connect 当时仍标记该项目为 `MISSING_METADATA / DRAFT`，这是独立的发布资料状态，不把价格一致性写成项目已可送审。

### 已通过的真实交互

- **Mac 付款取消：通过。** 从正式 `ProductView` 打开 Apple 系统付款流程并取消，App 返回免费态“升级”，没有错误解锁；随后仍可重新发起购买。
- **Mac 真实 Sandbox 买断：通过。** 用户明确反馈“Mac 已购买”“购买完成”，随后原生可访问性树读取 `settings.entitlement.state.owned`，值为“已解锁”。
- **Mac 冷启动恢复：通过。** 完全退出进程并确认不存在 ApiRelay 进程后重新启动，设置页仍为“已解锁”。
- **Mac 手动恢复：通过。** 点击“恢复购买”后，原生可访问性树读取 `settings.restorePurchases.result`，值为“已恢复购买”。
- **iPhone 跨设备自动恢复：通过。** 物理 iPhone `SYSTEM-MP` 在未点手动恢复前冷启动当前源码构建，设置页显示“已解锁”；这与同一 Sandbox 买断在新设备由 `currentEntitlements` 自动可用的口径一致。
- **iPhone 手动恢复：通过。** 用户本人完成系统 Sandbox 密码提示后明确反馈“iPhone 恢复完成”；完成画面 `/private/tmp/ApiRelay-iphone-manual-restore-complete-20261009.png` 同时显示“已解锁”和“已恢复购买”。

### 退款与撤权：仍未通过

- 为补真实退款证据，曾加入只在 `DEBUG && REFUND_ACCEPTANCE` 生效的一次性探针，且只有 `AppTransaction` 和目标产品交易都为 StoreKit 已验签、未撤销的 `.sandbox` 时才显示 Apple 原生 `refundRequestSheet`。
- iPhone 与 Mac 都成功进入 Apple 原生退款页，但页面加载后只显示“无法连接 / 重试”。iPhone 画面为 `/private/tmp/ApiRelay-iphone-refund-sheet-loaded-20261009.png`；iPhone 的自动坐标操作落回 App 底层界面，不能冒称点中了系统页“重试”。Mac 通过原生可访问性按钮确认点击“重试”一次，等待后仍为“无法连接”。关闭页面只得到 `userCancelled`，没有提交退款。
- 因此**真实 Sandbox 退款、`revocationDate` 更新及退款后撤权均未完成**。清除购买历史不能代替退款；Apple 支持案例 `102975484910` 继续作为外部跟进。退款阻塞存在时不得宣布阶段 7 通过或关账。

### 清理、干净包和数据副作用

- 一次性退款探针已从源码完全撤除；`rg` 未找到 `REFUND_ACCEPTANCE`、`refundAcceptance` 或“Sandbox 退款验收”。干净 iOS Debug 已从当前源码构建并安装，设置页截图 `/private/tmp/ApiRelay-iphone-clean-settings-mid-20261009.png` 显示“已解锁”，没有退款入口。
- 干净 Mac Debug 从当前源码在 `/private/tmp/ApiRelay-v11311-clean-mac-20261009/Build/Products/Debug/ApiRelay.app` 构建成功，`codesign --verify --deep --strict` 通过；可执行文件不含退款探针标记。启动后原生可访问性树再次读取“升级 / 已解锁”。第一次受限沙箱内构建仅因 `sandbox-exec` 阻止 Swift 宏插件失败；相同命令在获准的正常 Xcode 环境退出码为 0，不记成源码失败。
- **必须保留的操作事故：** 部署一次性 iPhone 验收包时曾使用替换重装命令，导致 iPhone 本机 App 容器和设备本地偏好被重置。之后观察到账户列表为空、应用密码/自动锁/剪贴板等本机偏好回到默认；本轮未执行应用内“清除全部数据”、CloudKit 删除或 Sandbox 购买历史清除。Keychain 明文及设备本地偏好不能假定会由云端自动恢复，后续需由用户从可信备份恢复或重新录入。最终干净包使用保留现有容器的安装方式，但不能逆转此前重置。

### 当前停止点

- `git diff --check` 通过；退款探针已删除。工作包检查器现已退出 **0**，AppIcon 暂存与实施树 Xcode Cloud manifest 阻塞已经解除，外部内容未丢弃。
- 首次 Catalyst 完整套件的历史宿主异常退出仍未找到根因；本轮新增 20/20 单项和 640/640 完整通过证据，用户已接受“未复现但未定位”的残余风险。另发现并修复 3 个 snapshot 用例连接共享已购测试商店的隔离缺陷，不把它和历史宿主退出混为一谈。
- 当前准确结论：Mac 真实取消、购买、冷启动、手动恢复，iPhone 跨设备自动恢复、手动恢复，以及 iPad 购买 UI 均已有通过证据；检查器和旧文档冲突已解决。真实退款及退款后撤权仍阻止最终验收和关账，新的独立验收尚未执行。

方法观察：真实购买验收中，一次性诊断包必须默认采用保留容器安装；`reinstall` 会把本地数据恢复问题混入购买测试。此事故已按事实记录，但不在本购买任务内静默修改通用治理规则。

## 2026-09-29 本轮补查：额度提示警告与取消防回退

本轮用户重新授权检查优化手机端，下节“暂停手机端、没有修改”仅对应较早电脑复核。本轮仍在独立 `v1.13.11 @ 0f00255bc380eab8d5ff80c8e6145e5b28641172`，未提交、推送或关账。其他工作树和既有 AppIcon 暂存差异不动。

### 定位与最小改动

- iPhone / iOS 27 全套曾 **654/654**，但额度提示点击购买入口仍产生 `Publishing changes from within view updates is not allowed`；结果包 `/private/tmp/ApiRelay-v11311-ios-shared-regression-20260929.xcresult`。此前只延后展示购买页未解决警告，已撤回该处理。
- 延后弹窗 Binding 模型回写后，购买路径重复 **2/2**、无 runtime warning；最终改为更明确的局部 `@State` 展示状态，响应模型请求，退场后下一主队列循环复位模型。生产改变仅在 `VaultHomeAlertsModifier`；不改购买授权/认证/同步/数据语义。
- 新增两次连续取消回归最初在 iOS 27 / iPadOS 18 都失败。完整截图及层级最终证明购买弹窗实际已关闭，`app.alerts.firstMatch` 随后匹配既有 `vault.lock.cover` Alert 节点；不是取消失效。此前录像中淡出弹窗也不能作为永久残留证据。最终选择器排除该明确非购买安全节点，直接验证真正额度提示消失、不打开新增或付费页且再次仍拒绝。
- 为调查曾增加显式关闭按钮动作，取得层级证据后撤回；没有为测试误判留下生产补丁。未修改安全遮罩，未放宽任何权益断言。
- 中间失败仍保留：`ios-final-binding`（654/655）、`ios-quota-localstate`、`ios-quota-explicit-exists`、`ios-quota-explicit-dismiss`、`ipad18-quota-explicit-dismiss`、`ipad18-cancel-hierarchy`；完整路径均为 `/private/tmp/ApiRelay-v11311-名称-20260929.xcresult`。最后一包包含 `quota-cancel-hierarchy` / `quota-cancel-screen` 直接证据。失败来自错误的弹窗选择，不倒写为通过。

### 已读取证据

| 检查快照 | 结果 | 结果包 |
| --- | --- | --- |
| 中间 Binding 快照，原生 Mac 全套 | **654/654**，0 失败/跳过/runtime warning | `/private/tmp/ApiRelay-v11311-native-final-binding-20260929.xcresult` |
| 最终局部展示状态生产代码，Catalyst 全套 | **654/654**（640 单元 + 14 UI），0 失败/跳过/runtime warning | `/private/tmp/ApiRelay-v11311-catalyst-localstate-full-20260929.xcresult` |
| 同一生产代码，原生 Mac 全 UI | **14/14**，0 失败/跳过/runtime warning | `/private/tmp/ApiRelay-v11311-native-localstate-ui-20260929.xcresult` |

以上后两包早于移动端选择器排除安全节点和失败附件补充；生产代码相同，测试源码不完全相同。并行手机/平板构建共用 DerivedData 导致 `ipad18-final-purchase-ui` 构建数据库锁定（未执行测试）；已按顺序重跑，不记为产品断言失败，也不关闭闸门。

最终停写源码清单再摘要（`git ls-files -z --cached --others --exclude-standard -- ApiRelay | xargs -0 shasum -a 256 | shasum -a 256`）：`5a0a5dc22f34294fa1405710a8892cac7c01e768393d9d288afc3cd6ce372abe`。最终测试前后相同；本轮没有继续修改生产或测试源码。

| 最终冻结源码检查 | 实际读取结果 | 结果包 |
| --- | --- | --- |
| iPhone 17 Pro / iOS 27 全套 | **655/655**（640 单元 + 15 UI），0 失败/跳过/runtime warning；含本地 StoreKit 3/3、购买 UI 11/11 | `/private/tmp/ApiRelay-v11311-ios-final-precise-quota-20260929.xcresult` |
| iPad 10 / iPadOS 18 购买 UI | **11/11**，0 失败/跳过/runtime warning；含连续取消和购买后第四把 | `/private/tmp/ApiRelay-v11311-ipad18-final-purchase-ui-serial-20260929.xcresult` |
| 原生 Mac 取消 + 购买后第四把，各两轮 | **4/4 次**通过（2 个唯一用例），0 失败/跳过/runtime warning | `/private/tmp/ApiRelay-v11311-native-final-quota-repeat-20260929.xcresult` |
| Catalyst 同两用例，各两轮 | **4/4 次**通过（2 个唯一用例），0 失败/跳过/runtime warning | `/private/tmp/ApiRelay-v11311-catalyst-final-quota-repeat-20260929.xcresult` |
| 最终独立 Mac Debug 构建与签名 | 构建成功，Apple Development 签名，`codesign --verify --deep --strict` 通过 | `/private/tmp/ApiRelay-v11311-sandbox-mac-final-20260929/Build/Products/Debug/ApiRelay.app` |

以上 runtime warning 为结果包运行期记录，不代表此前 StoreKitTest 弃用/链接编译警告消失。此次未重新执行 iPad 完整单元或实体 iPhone 付款，不扩大通过范围。

### 真实 Sandbox 边界与环境

已构建、校验签名并启动独立 Mac 开发包 `/private/tmp/ApiRelay-v11311-sandbox-mac-20260929/Build/Products/Debug/ApiRelay.app`；此包早于本节提示状态修改，仅作商店入口准备，不冒称本轮最终验收包。App 停在身份确认/隐私界面，已请用户本人用 Touch ID / 系统密码解锁，尚未收到已解锁确认，没有真实付款。测试认证 fixture 不用于真实 Sandbox。

按 Apple [Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)，现代 Mac 首次 IAP 后可在 App Store 设置登录 Sandbox 测试账户，无需退出正常账号。本轮只读查看设置，没有修改账号。用户现有 Xcode 正在根工作树 `v1.13.12` 运行同 bundle ID App，可能干扰宿主，但不能据此断言它就是首次 Catalyst 退出原因；未停止会话、杀进程或清数据。

后续：更新最终签名包→用户本人解锁/系统 Sandbox 登录→确认交易环境→真实免费态新购、系统取消、冷恢复、退款撤权与跨设备。自动回归不能制造 Apple 后台结果或代替设备主人认证。

本轮末已更新并通过原生 UI 工具打开上表 **final** 签名包，实际界面仍是“需要身份确认”的隐私罩；窗口 Raise 后截图也未变为内容页。未绕过认证、未操作账户或付款。当前下一步为用户本人把这一最终测试窗口切到前台并解锁，而非继续在旧包上验收。早先包保留作准备历史，不覆盖正在运行的 App。

`git diff --check` 与 `selfcheck.sh` 红线通过。只读工作包检查器仍退出 **4**：`只读快照工作树存在暂存差异`；根工作树 `v1.13.12` 的 AppIcon 暂存内容为既有用户差异，保留，不放宽契约。真实 Sandbox、首次 Catalyst 退出根因、另一角色独立验收仍未完成。

## 2026-09-29 电脑端复核：自动回归通过，仍未彻底验收

用户要求先确认电脑端，暂停手机端。此次没有继续手机测试，也没有新增产品代码修改、提交或推送。测试对象是 `v1.13.11 @ 0f00255bc380eab8d5ff80c8e6145e5b28641172` 加现有未提交修改，运行环境为本机 Apple Silicon Mac / macOS 26.7.1（25G241）/ Xcode 27.0（27A266a）。测试前后 `ApiRelay/` 全量受控与非忽略新文件 SHA-256 清单再摘要均为 `f55f436a3e2a107bee0072ebf10f3c4a3d05cd25863dd217dd46cd07ec401d9c`，没有在重跑中改变产品源码。

此前桌面测试兼容处理已经存在于当前源码：原生 Mac 与 Catalyst 的本地 StoreKit 测试通过外部购买 API 驱动同一测试商店，再从 `Transaction.currentEntitlements` 取得已验签交易；测试没有伪造交易或放宽生产授权。桌面恢复反馈按系统实际暴露的 `label` / `value` 检查；额度提示的付费按钮限定在当前弹窗内，避免点到后面的同标识按钮。第四把额度测试在桌面使用自动生成名称，避免 XCTest 合成普通文本输入的系统警告；它验证购买后新增及保存，不代表另行验证了人工输入名称。共用的额度提示弹窗入口已在此前改成下一个主队列循环展示付费页，本次桌面完整回归覆盖该最终实现。

| 本次检查 | 实际结果 | 结果包 |
| --- | --- | --- |
| 原生 macOS 完整测试 | **653/653 通过**：单元 640/640、界面 13/13；0 失败、0 跳过、0 runtime warning；包含原生本地 StoreKit 3/3、购买 UI 10/10 | `/private/tmp/ApiRelay-v11311-desktop-native-20260929.xcresult` |
| Mac Catalyst 首次完整测试 | **652/653 通过、1 失败**；单元 639/640，界面 13/13；0 跳过、0 runtime warning；本地 StoreKit 3/3 通过 | `/private/tmp/ApiRelay-v11311-desktop-catalyst-20260929.xcresult` |
| Catalyst 失败用例单独连续复测 | `SecureBackupTests.testUnprotectedExportImportRoundTrip` **5/5 次通过** | `/private/tmp/ApiRelay-v11311-catalyst-backup-repeat-20260929.xcresult` |
| Catalyst 完整单元连续两轮 | 每轮 **640/640 通过**，合计 **1280/1280 次通过**；0 失败、0 跳过、0 runtime warning | `/private/tmp/ApiRelay-v11311-catalyst-unit-repeat-20260929.xcresult` |
| 静态检查 | `selfcheck.sh` 红线、`git diff --check`、任务契约 JSON 解析通过 | 命令执行输出 |

首次 Catalyst 失败必须保留，不能以复测覆盖：Xcode 报告测试宿主在该用例开始后提前结束，退出码 0，随后重启宿主继续执行剩余测试；没有备份往返断言失败或源码错误栈。系统 RunningBoard 日志确认 PID 9039 在 15:48:20.293 由 launchd 报告 `termination (0, 0, 0)`。单项五次和完整单元两轮均未复现，当前证据尚不足以确定退出发起者或根因，因此登记为**未定位的测试宿主提前退出问题**，没有凭猜测修改备份生产实现，也没有把首次失败写成通过。

编译还包含 Apple StoreKitTest 头文件弃用警告，以及 Catalyst 测试 target 链接该框架的 macOS dylib 警告。它们是本次实际编译输出；结果包的 `runtimeWarnings: []` 不能解释为编译完全无警告。旧的 9 月 28 日桌面结果包在本轮已无法从临时路径读取，以上均为 9 月 29 日新跑并实际读取的证据。临时结果包不保证长期保留，本节保存精确统计与源码摘要。

结论：当前电脑端已发现的购买流程与测试兼容问题已有修改，常规自动回归获得通过证据；**电脑端尚不能称为彻底完成**。仍需闭环这次 Catalyst 宿主退出的稳定性问题，并完成电脑端真实 Sandbox 免费态付款、系统取消、冷恢复、退款撤权和跨设备恢复。界面测试使用 DEBUG 可控商店边界；StoreKitTransactionTests 使用 Xcode 本地测试商店。上述结果没有验证正式原生 `ProductView` 的真实商店付款面板，不等于真实 Sandbox 通过，也不构成独立审计或关账。

## 2026-09-28 追加实施复核：双重商品加载与测试会话隔离

本轮只在 `v1.13.11` 修改产品代码；`v1.13.12`、`v1.14`、`v1.15` 继续作为只读规划快照。误提交的本地 `v1.13.9 @ aee2f8a` 已保全到可恢复分支 `codex/archive-v1.13.9-aee2f8a`，本地 `v1.13.9` 已恢复为远端冻结 SHA `25fe006`，因此此前隔离检查的该项漂移已经按用户授权消除。

代码已改为单次加载并复用原生 `Product`，业务协议不再依赖 `Product.PurchaseResult` 或默认创建真实 StoreKit 客户端，权益变化改为带来源和修订号的实例级异步事件，并让迟到订阅者收到最后事件。Test Action 保持唯一 `.storekit` 环境绑定，原生测试的 `SKTestSession` 负责控制同一测试环境；曾移除 Scheme 绑定的诊断尝试已撤回，Scheme 最终无相对 HEAD 差异。

新证据为：iOS 18 完整单元 640/640、原生 StoreKit 3/3、购买 UI 10/10；iOS 26.5 购买 UI 10/10；iOS、原生 Mac、Catalyst Release 均构建通过。iOS 26.5 原生 StoreKit 仍为 0/3，三项均在测试代码的 `session.buyProduct(...)` 处返回 `notEntitled`，发生在应用适配器和权益授予之前。对应结果包路径详见 `06-本地实施报告.md`。

这是一轮实施者自检，不是另一角色独立审计。真实 Sandbox 免费态购买、取消、退款与撤权、冷恢复及 Mac 付款仍未完成；Apple 支持案例 `102975484910` 仍是外部阻塞。购买阶段继续不得关账。

### iOS 26.5 `notEntitled` 最终定位与处理

- Apple DTS 已确认 iOS 26.5 命令行 StoreKit Test 配置同步是已知系统问题，见 [Apple Developer Forums / FB22237318](https://developer.apple.com/forums/thread/826971)。本项目三项均在 `session.buyProduct` 处先失败，与该故障边界一致；不是 `EntitlementService` 拒绝交易。
- 使用 Xcode 官方下载器安装 iOS 27.0（24A434），创建全新 iPhone 17 Pro 模拟器 `A6AFB97C-179B-405A-AFEE-047A7143F4E9`。移除 Test Action 配置时，交易无法进入 App 的 `currentEntitlements`；恢复 Apple 官方要求的唯一 `ApiRelay.storekit` Scheme 绑定后，原生交易 **3/3 通过**，结果包 `/private/tmp/ApiRelay-v11311-storekit27-scheme.xcresult`。
- 同设备完整单元 **640/640 通过**，结果包 `/private/tmp/ApiRelay-v11311-unit27.xcresult`；购买 UI **10/10 通过**，结果包 `/private/tmp/ApiRelay-v11311-purchase-ui27.xcresult`。UI 结果包另记录一条仅 iOS 27 出现、无源码位置的 SwiftUI 视图更新期发布警告，Xcode 后置诊断收集超时，但测试和 `xcodebuild` 均为 Passed；该警告已保留，未冒称不存在，也未在无定位条件下扩大代码修改。
- iOS 26.5 的 0/3 结果继续保留，不删除、不跳过、不写成通过；该运行时只承担不依赖原生 `SKTestSession` 配置同步的 UI/状态回归。
- 未改生产授权策略：普通 App 仍拒绝 `.xcode` 假交易，必须是目标产品、StoreKit 已验签、未撤销；本地 snapshot 仍不是授权依据。解决的是测试运行时与 Scheme 环境绑定，不是绕过 `notEntitled`。

## 2026-09-28 第二步：购买代码开发检查点复核

用户本轮明确授权在 `v1.13.11` 提交并上传当前购买代码检查点，并明确这只是保存当前成果，不代表购买阶段关账。提交前在冻结源码上重新完成以下验证：

- 签名 iPad 10 / iOS 18.0 完整单元测试 **639/639 通过，0 失败、0 跳过**，产物 `/private/tmp/ApiRelay-v11311-checkpoint-unit.xcresult`；
- iPhone 16 Pro / iOS 18.0 完整 UI **14/14 通过**，iPad A16 / iOS 26.5 完整 UI **14/14 通过**，产物分别为 `/private/tmp/ApiRelay-v11311-checkpoint-ui-full-iphone.xcresult`、`/private/tmp/ApiRelay-v11311-checkpoint-ui-full-ipad.xcresult`；
- 原生 Mac 与 Mac Catalyst 的 Release 构建通过；Release 可执行文件未发现 `APIRELAY_UI_TEST_SCENARIO`、`FakeStoreKitClient` 或 `UITestFixture`；
- 项目 `selfcheck.sh` 红线通过，检查器回归 **87/87 通过**，`git diff --check` 与任务契约 JSON 校验通过，暂存区为空；当前 `v1.13.11` 的全部修改和新增文件均在 `00C` 精确白名单内。

已知失败没有被隐藏：iPhone 17 Pro / iOS 26.5 的 3 项原生本地 StoreKit 测试仍为 **0 通过、3 失败**，均返回 `notEntitled`，产物 `/private/tmp/ApiRelay-v11311-checkpoint-storekit26.xcresult`。iOS 18 同组测试已包含在 639 项完整单元回归并通过；不能用它覆盖 26.5 的运行时差异。

真实 Sandbox 仍未完成：没有可核对的免费态基线，所以本轮未重新证明“免费→购买”及购买取消；已有交易上的手动恢复只证明流程完成后权益未丢失，不是冷恢复；系统退款页仍“无法连接”，没有完成退款与退款后撤权；Mac 桌面真实付款交互未测；Apple 支持案例 `102975484910` 仍待外部结论。Ask to Buy 的批准/拒绝保留为 Xcode 本地测试边界，不冒充真实 Sandbox 结果。没有 Archive、TestFlight、App 审核、`v1`/`main`/tag 推进，也没有另一角色独立验收。

工作包机械检查器仍因只读 `v1.13.9` 工作树从冻结快照 `25fe006` 变为本地 `aee2f8a` 而退出 4；该外部提交不属于本次 `v1.13.11` 差异，本轮不改写其归属、不重建冻结快照、不把检查器结果写成通过。当前用户授权仅覆盖精确提交并上传本购买开发检查点；该外部隔离问题与真实 Sandbox 项目继续阻止关账。

## 2026-09-28 成熟实现收敛：代码完成，关账仍受阻

授权：本轮用户要求按 GitHub 成熟项目与已拟方案有序实现，仅在独立 `v1.13.11` 修改购买权益；不提交、推送、迁移真实数据或操作商店后台。全部代码修改已停止；以下为实施者自检，**不是另一角色独立验收，也不是新一轮真实 Sandbox 验收**。

### 实际采用与参考

- 实际使用 Apple 原生 `ProductView` 作为正式购买组件，参考 [apple/sample-backyard-birds 的 BirdFoodShop](https://github.com/apple/sample-backyard-birds/blob/1843d5655bf884b501e2889ad9862ec58978fdbe/Multiplatform/Shop/BirdFoodShop.swift)。原生组件自行发起付款，回调只处理结果，不再重复调用 `Product.purchase()`。
- 参考 [RevenueCat/purchases-ios 的 StoreKit2TransactionListener](https://github.com/RevenueCat/purchases-ios/blob/a2465d4abaea95560d48bfb14ebcd4dbf8304500/Sources/Purchasing/StoreKit2/StoreKit2TransactionListener.swift) 及其测试，统一直接购买和异步交易入口、保留验证与完成交易边界、注入 StoreKit 适配器并测试迟到/重复/撤销事件。审阅的是以上固定 SHA，不声称整个 RevenueCat SDK 已接入；未新增托管后台或第三方运行依赖。
- 未采用已缺持续维护的 SwiftyStoreKit。Dropbox/StoreKitTestHelpers 只参考有界等待，不引入其订阅专用判断或超时跳过逻辑。

### 新实现与检查中修复的问题

1. 新增 `StoreKitClient` 和仅 DEBUG 测试可用的 `FakeStoreKitClient`。生产适配器只把 StoreKit 已验签结果转为有效证据。本机 `EntitlementSnapshot` 始终不是授权来源；普通 App 继续拒绝 `.xcode` 假交易。
2. 新增单一 `EntitlementStore`，由组合根持有。设置页、付费墙共享核对中/免费/已购/不可核对状态，商品加载单独管理；忙碌期间到达的交易变化在操作结束后补核对，迟到查询不能覆盖新结果。
3. 直接购买成功和 `Transaction.updates` 都进入同一验证入口。已验签购买允许最多 5 秒的进程内衔接，支持立即新增第 4 把；重复结果不延长期限，退款及显式恢复终止衔接，验签未知不能被掩盖。衔接到期自动触发重新核对，不持久化成永久会员。
4. 取消后同页可继续购买；pending 必须经显式“核对批准状态，允许再次尝试”才能再发起。空交易序列不能被当成 Ask to Buy 拒绝。商品元数据和原生购买组件均可同页重新加载；商品重载不能擦掉待批准提示。
5. 列表在权益变化后重新计算额度，新增前再次查业务额度。启动异步维护不再覆盖用户已切换的页签；当前值订阅跳过初始重放，避免额度查询被界面重订阅持续触发。新增路径与现有业务最后写入检查共同保护，不让 UI 的“已购”直接放行业务。
6. UI fixture 现在运行真实 `EntitlementService` 与真实 `KeyVaultService`，仅 Apple 接口、存储与身份交互替换为测试边界；不再以互不关联的无限 FakeVault 和免费 FakeEntitlements 证明购买闭环。界面测试实际走“已有 3 把 → 新增被拦截 → 购买 → 不离开流程再次新增 → 第 4 把保存成功”。
7. 修复测试查出的容器可访问标识覆盖按钮、动态权益标识定位失效、重复等待同一 XCTest expectation 等测试底座错误。旧失败产物保留，未以跳过断言或关闭验签获取通过。

### 最终冻结源码证据

分支及 HEAD 仍为 `v1.13.11 @ 47626b1930bcb227804c6caf9f37e05768a234e8`，包含本轮未提交改动；暂存区为空。本轮没有 commit、push、合并、tag、Archive、TestFlight 或审核操作。最后只读 `git ls-remote --heads origin v1.13.11` 仍返回该 SHA，未把本轮本地修改冒称已上传。

- 全部 `ApiRelay/` 受控文件与非忽略新文件的 SHA-256 清单再摘要：`b45263c81657c668ad477e6eb364e85ba7e56526daf13e2441b73aee521c593f`。
- 重建命令：`git ls-files -z --cached --others --exclude-standard -- ApiRelay | xargs -0 shasum -a 256 | shasum -a 256`。文档续记不进入这个源码摘要；最后测试与停写复核时摘要一致。
- 相对 HEAD 的已跟踪 `ApiRelay/` 二进制 diff 摘要：`fad7dc0edfc5bb1c72d9cb2b680b6d4f70bb0a6a394346fbdaf21b8df0cec8bd`；四份新增 Swift 文件另纳入上述全量摘要。
- 测试均正常开发签名；没有用 `CODE_SIGNING_ALLOWED=NO`，没有新设生产授权后门。Release 的 Mac / Catalyst 二进制字符串核对未出现 `APIRELAY_UI_TEST_SCENARIO`、`FakeStoreKitClient` 或 `UITestFixture`，但此静态核对不冒充运行验收。

| 冻结后检查 | 实际结果 | 可复核产物 |
| --- | --- | --- |
| iPad 10 / iPadOS 18 完整单元，包括 20 项新流程回归和 3 项原生本地 StoreKit 测试 | 639/639，通过，0 失败、0 跳过 | `/private/tmp/ApiRelay-v11311-wheel-unit-frozen.xcresult` |
| iPhone 16 Pro / iOS 18 全套 UI（购买 10 + 冻结安全 4） | 14/14，通过，0 失败、0 跳过 | `/private/tmp/ApiRelay-v11311-wheel-iphone-ui-final.xcresult` |
| iPad A16 / iPadOS 26.5 全套 UI（同上） | 14/14，通过，0 失败、0 跳过 | `/private/tmp/ApiRelay-v11311-wheel-ipad-ui-final.xcresult` |
| iPad 10 第 4 把实际 UI 闭环定向 | 1/1，通过 | `/private/tmp/ApiRelay-v11311-wheel-ipad18-quota-focused.xcresult` |
| 原生 Mac Release 编译 | 通过，正常签名 | `/private/tmp/ApiRelay-v11311-wheel-release-mac` |
| Mac Catalyst Release 编译 | 通过，正常签名 | `/private/tmp/ApiRelay-v11311-wheel-release-catalyst` |
| 工作包检查器回归 | 87/87，通过 | `python3 -B -m unittest discover -s ZL00_项目总控/自动化 -p test_check_multi_ai_workflow.py` |
| iPhone 17 Pro / iOS 26.5 原生 StoreKit 3 项 | **0 通过、3 失败、0 跳过；均 notEntitled** | `/private/tmp/ApiRelay-v11311-wheel-storekit26-current.xcresult` |
| 差异空白及本地化 JSON | 通过 | `git diff --check`、`jq -e` |

中间失败也保留：首轮界面 3/9 通过、定向 2/4 通过、第二轮手机 6/10 通过；修复后才得上述最终 14/14。中间单元 638/639 的失败为对异步补核对尚处 checking 的瞬间断言；改为有界等待真实收敛后完整 639/639，并在最终源码再次跑 639/639。旧定向 `wheel-iphone-ui-focused2` 在 Xcode 测试收尾挂起后由本任务仅中断自己的进程，**不记为通过**。没有停止用户其他 Xcode 会话或卸载 App。

最终单元命令（其余测试仅换目标/产物/`only-testing`）：

```sh
xcodebuild -quiet test -project ApiRelay/ApiRelay.xcodeproj -scheme ApiRelay \
  -destination 'platform=iOS Simulator,id=40368036-2408-4031-A055-79C138E512ED' \
  -derivedDataPath /private/tmp/ApiRelay-v11311-wheel-unit \
  -resultBundlePath /private/tmp/ApiRelay-v11311-wheel-unit-frozen.xcresult \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 120 -only-testing:ApiRelayTests \
  CODE_SIGN_IDENTITY='Apple Development' -allowProvisioningUpdates
```

### 剩余阻塞与停写边界

- **隔离闸门新阻塞**：本轮进入时检查器退出 0；最终核对退出 **4**，报原只读工作树 HEAD 偏离快照。原树实际为 `v1.13.9 @ aee2f8ab17390a909e83af040e1e3e1abd4d886b`，不再是契约保留的 `25fe006`。只读查看确认新提交父级为 `25fe006`，时间 **2026-09-28 16:22:24 +0800**，标题 `Add project governance and release documentation`，实际包含 **1183 个文件**，包括原购买差异 `SettingsView.swift`、`Localizable.xcstrings`、`project.pbxproj` 以及历史测试产物。它不是本任务创建的提交；本任务没有移植、清理、回退或推送它。不能因标题为文档就认定隔离无变化。
- 原始基线及冻结 HEAD / fingerprint 契约**原样保留**；未放宽检查器，也未把新 SHA 覆盖为“已授权新基线”。`v1`、`main`、`v1.13.10`、`v1.14` 及其追踪 refs 未漂移；`origin/v1.13.9` 仍为 `25fe006`。后续须先由负责人确认该新提交归属和保全方式，再明确授权重建隔离快照、重验闸门；本任务现在停止。
- iOS 26.5 的 `SKTestSession` 本地测试依旧 `notEntitled`，未关闭验证、改普通 App 允许 Xcode 假交易或跳过测试来掩盖。Apple DTS 曾确认[相关测试配置问题](https://developer.apple.com/forums/thread/826971)，其答复与开发者报告还讨论 SDK / runtime 版本差异；**这只是测试环境调查线索，不足以认定本项目 notEntitled 与论坛问题同一根因**。本轮以 iOS 18 的真实本地 StoreKit 测试取得有效回归，同时保留 26.5 的失败，不把 UI fixture 14/14 当成该框架通过。
- 未重新安装或操作两台真机，没有要求创建、切换或清除 Sandbox 账号，也没有重新购买。历史 Apple 退款表单无法连接、真实免费态购买 / 冷恢复 / 退款撤权欠验收，以及支持案例 `102975484910` 的回复状态保持原边界。
- Mac 两种形态完成编译但未做桌面界面 / 真实付款验收；不申请控制电脑权限。没有另一角色签字。**本阶段不得宣布关账或发布，不能承诺“永无后患”。**

以下为 2026-09-25 的原始记录，保持其历史快照语义。

日期：2026-09-25；分支：`v1.13.11`；产品代码 HEAD：`47626b1930bcb227804c6caf9f37e05768a234e8`；原始基线：`8e6c22109b9f5851dacb31b96e8915d855b0e0f3`。本页是同一执行者复核，不是工作包阶段 5/7/9 所称的独立角色签字。

## 已核对

- `git ls-remote --heads origin v1.13.11` 返回 `47626b1930bcb227804c6caf9f37e05768a234e8`；原始基线是该提交的祖先，两笔提交依次为 `1556e17`、`47626b1`。精确文件清单由两笔 `git show --format= --name-only` 核对；没有把原 `v1.13.9` 脏树文件带入本分支。
- 本地结果包重新读取：完整单元 615/615、iPhone 购买 UI 5/5、iPad 购买 UI 5/5、本地 StoreKit 交易 1/1，均零失败。这些结果只证明对应本地测试，不代表真实 Sandbox。
- 权益写入边界仍由 `KeyVaultService.ensureCanActivateKeys` 重新读取 StoreKit 决定；UI 的 `EntitlementDisplayState` 和本地 snapshot 不是授权来源。代码核对覆盖购买返回后等待 `currentTier()`、恢复购买、退款撤权、免费额度三把与查询失败显示。未发现本轮代码范围外被顺手修改的认证、云同步实现或产品 ID。
- 2026-09-25 在用户确认已备份、允许覆盖安装后，以同一产品源码构建开发签名 iOS 包（命令行临时指定 `CURRENT_PROJECT_VERSION=11`，仓库项目版本不变），签名验证通过；iPhone 15 Pro Max 与 iPad Pro 13-inch (M4) 均从既有 App 覆盖安装到 `1.0.1(11)`，没有执行卸载或清除数据。两台设备的 `devicectl` 安装和启动均成功。

## 尚未通过的真实场景

- 产品负责人已准备 Sandbox 账号及商品，iPhone“设置 → 开发者 → Sandbox Apple 账号”显示测试账号已登录。用户第一次尝试时未看到 Sandbox 标识并取消；随后只读截图核对发现实际停在 App 设置页，并未打开系统付款确认页，且“升级”已显示“已解锁”。用户确认这是可能有历史购买的旧测试账号。**没有发生本轮新购买，现有已解锁也不能冒称本轮真实 Sandbox 交易通过。** Apple 文档中的环境标记是登录场景提示，不应误写成每次购买面板必现；仍需核对历史交易来源。
- 用户在同一构建号 11 的 iPad 上观察到“升级”本来已解锁，点击“恢复购买”后仍为已购且无报错。这是**已购显示与恢复操作成功**的用户观察，不是“未购→已购”的冷恢复证明；两台设备可能同有旧测试交易，尚不能判定具体交易环境。
- 后续刷新 App Store Connect 页面后实际列出测试账号，纠正了此前“账户列表为空”的判断。产品负责人创建了一个新的、可收信的 Sandbox 测试账号，并在两台设备的「设置 → 开发者 → Sandbox Apple 账号」登录。另两条误建的旧 Sandbox 测试账号经产品负责人逐项确认后删除；未清除新账号购买历史，也未删除设备 App 或密钥数据。账号邮箱不写入公开工作包。
- iPhone 本轮新购买、取消后的状态、待批准、退款；iPad 冷恢复及退款后的撤权；Mac 桌面交互都还没有真实通过结果。不得根据本地 StoreKit 结果宣布这些项目通过。
- 直到真实场景完成且验收角色要求得到满足，`v1.13.11` 不关账、不推进 `v1`、不开始 `v1.14` 实施，不做 Archive、TestFlight 或商店审核。

## 2026-09-25 后续测试进展（仍非关账）

- 修复发现的第四把密钥配额入口缺口：加密备份导入现在与普通新增共用权益校验，免费状态导入第四把会完整回滚，已拥有的超额密钥不会被删除。普通 Xcode Run 不再自动加载本地 `.storekit`，Test Action 仍保留本地 StoreKit 测试。
- 新增 2 项备份导入配额单元测试；签名环境完整单元测试 617/617 通过，结果包 `/private/tmp/ApiRelay-v11311-entitlement-fix-all-unit-signed.xcresult`。iPhone 购买 UI 5/5、iPad 购买 UI 5/5，结果包分别为 `/private/tmp/ApiRelay-v11311-entitlement-fix-iphone-ui.xcresult` 与 `/private/tmp/ApiRelay-v11311-entitlement-fix-ipad-ui-final.xcresult`。Mac 原生与 Mac Catalyst 编译通过。上述仍是本地 fixture，不冒充真实 Sandbox。
- 同一分支源码构建开发签名 `1.0.1(12)`，在用户确认备份和覆盖安装授权后，保留数据覆盖安装并启动两台真机。新账号初次查看时两台均仍显示“已解锁”；未据此执行付款或认定冷购买成功。iPhone 追加匿名 StoreKit 环境诊断的 `1.0.1(13)` 后，启动日志两次显示 `no accepted current entitlement`，设备主界面重新显示免费额度为 0 且有“解锁无限密钥”入口，既有 4 把密钥仍保留。正在核对升级页实时状态和后续交易环境；诊断输出只保留在已安装的测试包，源码中的临时诊断改动已移除。
- 同一 iPhone 诊断包随后在未重新安装的情况下，`Transaction.currentEntitlements` 返回产品 `com.apirelay.iap.unlimited_keys` 的已验签、未退款 `.sandbox` 交易，`AppTransaction` 环境同为 `.sandbox`，设置页再次显示“已解锁”。因此可排除本地 snapshot 直接放行，也可排除本地 `.xcode` 假交易；**尚不能由交易环境推断是哪一个 Sandbox 账号的交易**。App Store Connect 的新测试账号在“活跃”筛选中出现，按 Apple 文档通常意味着近 180 天完成过测试购买，但页面未给出足以核对交易 ID 或归属的详情。现等待设备上执行一次“恢复购买”触发 `AppStore.sync()` 后观察；未清除新账号购买历史。
- iPhone 执行“恢复购买”后仍为“已解锁”；日志在同步后继续读到已验签、未退款的 `.sandbox` 买断。进一步使用仅输出购买日期的临时诊断包 `1.0.1(14)`：该交易购买时间为 **2026-09-25 04:18:02 UTC，即北京时间 12:18:02**，发生在新 Sandbox 账号创建及登录之后，排除“几周前购买日期的旧交易”解释；但 StoreKit 交易不提供可直接核对的测试账号邮箱，不把时间相关性冒充账号归属证明。新账号在 App Store Connect“活跃”筛选结果中出现，构成旁证。源码中的临时日期日志已移除，只有设备上诊断包含该输出。
- 同一 `1.0.1(14)` 已保留数据覆盖安装到 iPad；设备当时锁屏，系统拒绝远程启动，尚未读到 iPad 交易日期。待解锁后比对购买日期，再验证跨设备恢复及退款撤权。
- iPad 解锁后读取到的不是 iPhone 的 12:18 Sandbox 交易，而是购买日期 **2026-09-23 17:52:34 UTC** 的 `.xcode` 本地 StoreKit 假交易。临时 `1.0.1(15)` 诊断进一步确认 iPad 的 `AppTransaction` 环境也被缓存为 `.xcode`，旧规则因此返回 `accepted=true`；这就是 iPad 无真实跨设备购买却显示“已解锁”的直接根因。不能把原先两台设备的“已解锁”记作跨设备成功。
- 在独立工作树最小修复：普通 App 实例默认一律拒绝 `.xcode` 假交易，即使 `AppTransaction` 也为 `.xcode`；StoreKit 自动测试须显式注入 `localStoreKitTestingAllowed=true`，Release 构建仍无条件拒绝。新增真实 `SKTestSession` 回归：同一假交易对测试实例有效、对普通 App 实例无效；保留原购买→第四把密钥→退款测试。签名模拟器定向交易测试 2/2、最终完整单元 618/618 通过；结果包分别为 `/private/tmp/ApiRelay-v11311-local-storekit-fence-storekit-regression.xcresult` 和 `/private/tmp/ApiRelay-v11311-local-storekit-fence-all-unit-final.xcresult`。
- 修复版 `1.0.1(16)` 已保留数据覆盖安装到 iPhone 和 iPad。iPad 当时停在 Face ID 失败弹窗，尚未完成手动解锁后的免费状态核对；iPhone 仍保留四把密钥。跨设备真实 Sandbox 交易、退款撤权及取消/待批准尚未完成，不能关账或上传。
- 最终代码再次通过 iPhone 购买 UI 5/5、iPad 购买 UI 5/5，结果包 `/private/tmp/ApiRelay-v11311-local-storekit-fence-iphone-ui.xcresult` 与 `/private/tmp/ApiRelay-v11311-local-storekit-fence-ipad-ui.xcresult`；Mac 原生、Mac Catalyst Debug 与 iOS Release 编译通过。iPad 真机当前仍在 App 身份验证页，用户需自行输入设备或应用密码；自动测试和编译不能替代这一项真实交互及后续 Sandbox 场景。
- iPad 临时诊断包 `1.0.1(17)` 在 App 身份验证页背后再次读取旧 9 月 23 日 `.xcode` 交易，明确输出 `accepted=false` 和 `no accepted current entitlement`，因此**真机已证明修复后不再把旧假交易当会员**；该时点尚未看到 iPhone 的 12:18 Sandbox 交易。临时日志已从源码移除，设备上的诊断包保留到 iPad 用户手动“恢复购买”实测结束。此处不把代码判定通过冒充 iPad UI 或跨设备恢复通过。
- 用户已解锁 iPad 并在 `1.0.1(17)` 设置页执行“恢复购买”；实际界面回到免费态并提示“未找到可恢复的购买”，不是闪退，也不是恢复成功。此前诊断只见 9 月 23 日 `.xcode` 假交易被拒绝，未见 iPhone 的 9 月 25 日 `.sandbox` 买断；**iPad 跨设备真实 Sandbox 恢复当前不通过**。`AppStore.sync()` 调用已返回但没有可放行交易，尚不能仅据此区分 Sandbox 账号会话、Xcode 本地测试环境残留或 Apple 侧同步问题；不清除 App 数据、不删除新账号购买历史、不声称根因已定。下一步只观察 iPad 系统付款面板是否明确标示 `[Environment: Sandbox]`，未标示则取消，确认环境后再针对性处理。
- 用户按上述最小探针在 iPad 打开系统付款面板，**未见 `[Environment: Sandbox]`，已立即取消，未确认付款**。Apple 官方说明开发签名 App 的 Sandbox 首购面板应显示该标识；本次不能认定已经进入 Sandbox。`1.0.1(17)` 包的 Team ID 为 `8NDLKZ4SSF`、Bundle ID 为 `com.apirelay.ApiRelay`，嵌入的开发描述文件包含两台设备 UDID，签名 `get-task-allow=true`；isolated scheme 的 Run Action 已移除本地 `.storekit`，Test Action 保留。原 `v1.13.9` 工作树的 Run Action 仍引用本地 `.storekit`，只读核对，不触碰原树。下一步仅让用户在 iPad 的「开发者→Sandbox Apple 账号」退出并重新登录同一新测试账号，再手动恢复；不退出个人 Apple 账号，不清除购买历史、不卸载 App。
- 用户补充的系统弹窗截图明确写着 **`[Environment: Xcode]`**（截图 `/Users/xitongzhili/Desktop/截屏 2026-09-25 14.17.34.png`），此前“只是不显示 Sandbox”因此纠正为 **iPad 确实被本地 StoreKit 测试会话占用**，不是生产付款环境。重新登录同一 Sandbox 账号仍恢复不到购买。`1.0.1(18)` 用命令行构建且从 App 包中排除 `ApiRelay.storekit`，核实包内无此文件；覆盖安装后付款弹窗依旧 `[Environment: Xcode]`。因此单靠退出/登录账号、移除包内文件或 `devicectl` 覆盖启动，均不能清掉设备已有的本地测试会话。
- 在 Xcode 里**只打开独立 `v1.13.11` 工程**，界面核对目标为 iPad、Scheme 的 Run → Options → StoreKit Configuration 为 **None**，然后从 Xcode IDE Run 一次（`1.0.1(19)`，临时构建号与匿名日志随后撤回）。iPad `AppTransaction` 与已验签买断交易随即都变成 **`.sandbox`**；购买时间为 **2026-09-25 04:18:02 UTC**，与 iPhone 真机上的 Sandbox 交易完全一致。iPad 设置页“升级”显示“已解锁”，截图 `/private/tmp/ApiRelay-v11311-ipad-sandbox-after-xcode-none.png`。停止 Xcode 调试后，使用 `devicectl` 独立重启同一包仍读取 `.sandbox`，排除只在调试器挂载期间暂时成功。Apple 的环境隔离方法见 [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)。
- 源码中的临时环境/日期 `print` 已删除；项目 `project.pbxproj` 的临时构建号 19 与测试文件排除设置也已恢复，**该文件无工作树差异**。再按正常工程设置命令行构建干净 `1.0.1(20)`，保留数据覆盖安装并独立启动 iPad，App 成功进入密钥列表（截图 `/private/tmp/ApiRelay-v11311-ipad-clean20-state.png`）；当时尚等用户核对“恢复购买”按钮。`v1.13.9` 原工作树的旧 Run 配置仍未触碰；若以后从原树向 iPad Run，可能重新注入本地测试环境，不能用它作本阶段 Sandbox 验收。
- 用户明确反馈：干净 `1.0.1(20)` **未点“恢复购买”**，仅重新打开 App 就显示“已解锁”。结合 iPad 与 iPhone 同一购买时间的已验签 Sandbox 交易，以及排除 `.xcode` 放行的修复，可记为**跨设备自动权益恢复通过**；手动恢复按钮在切换环境后的真实 Sandbox 操作仍未执行，不得记成通过。StoreKit 官方说明正常情况下交易在新设备启动时自动可用，`AppStore.sync()` 仅为用户怀疑缺交易时的显式恢复入口，见 [AppStore.sync()](https://developer.apple.com/documentation/storekit/appstore/sync%28%29)。
- 已有 iPhone Sandbox 交易、iPad 同一购买时间的自动跨设备权益与“已解锁”真机证据；**干净包手动恢复按钮、取消、待批准、退款及退款后撤权仍未全部验收**。当前差异只在独立 `v1.13.11` 工作树，本轮未提交或推送；不得宣称购买阶段关账。
- 用户随后在 iPad 干净包 `1.0.1(20)` 的设置页点击“恢复购买”：升级行先显示“核对中”、恢复行出现转圈；稍后转圈结束，升级行回到“已解锁”。点击前就已解锁，故这次只证明手动恢复流程被触发、结束后权益未丢失，**不是未购→已购的冷恢复证明**。用户未看到独立的“已恢复购买”结果提示；源码 `SettingsView.restorePurchasesFromSettings()` 正常返回时应在恢复行下方设置该文案。可能是行下方未进入视野，也可能是请求修订竞争导致结果未落到界面；目前没有足够证据区分，不记为已证实的 UI 缺陷或完整手动恢复通过，也不要求用户重复点击。后续在免费态回归时统一核对结果提示。
- 为避免结果藏在恢复行下方，本轮把恢复结果也显示在该行右侧，保留原下方完整文本；新增已购/免费两项 UI 测试，断言结果文字存在、可见且权益状态正确。iPad A16 iOS 26.5 与 iPhone 17 Pro iOS 26.5 模拟器的完整购买界面组各 **7/7 通过**，结果包为 `/private/tmp/ApiRelay-v11311-refund-probe-restore-ui-ipad.xcresult` 与 `/private/tmp/ApiRelay-v11311-refund-probe-restore-ui-iphone.xcresult`。这说明 fixture 条件下文案可显示，不把它冒称为用户那次真机缺提示的根因证明。
- 当前正式界面没有发起退款的入口。为执行已授权的真实 Sandbox 退款验收，曾在 `SettingsView` 暂时加入仅特殊 DEBUG 编译条件启用的测试按钮，要求已验签 `AppTransaction` 与非退款产品交易环境均为 `.sandbox` 才可调用系统 `refundRequestSheet`；用构建号 21 保留数据覆盖安装两台真机。iPad 与 iPhone 都进入 **Apple 系统退款页**，但加载后只显示“无法连接 / 重试”，截图 `/private/tmp/ApiRelay-v11311-ipad-refund-connect-error.png` 与 `/private/tmp/ApiRelay-v11311-iphone-refund-connect-error.png`；用户未提交退款，也不应记作退款或撤权通过。与 [Apple 开发者论坛另一开发者的相同现象报告](https://developer.apple.com/forums/thread/846103) 相似，但该报告不是 Apple 的故障确认，本项目也不能单凭截图断言原因在 Apple 服务器。当前只记录系统表单级阻塞，不用清除购买历史冒充退款。
- 临时测试按钮源码已撤除，独立构建干净 `1.0.1(22)`：Bundle ID `com.apirelay.ApiRelay`、Team ID `8NDLKZ4SSF`，可执行文件不含测试按钮文字或编译标记。两台设备由诊断构建号 21 **保留数据覆盖安装**到构建号 22，`devicectl` 确认安装成功、App 能启动且两台现有数据容器 UUID 不变；没有删除 App、清除密钥、购买历史或 Sandbox 账号。覆盖安装成功本身不冒充权益状态通过，下一条单列真机画面证据。
- 干净 `1.0.1(22)` 启动后的 iPad 设置页截图 `/private/tmp/ApiRelay-v11311-clean22-ipad-state.png` 显示“已解锁”，恢复行右侧和下方均可见“已恢复购买”，没有临时退款入口；iPhone 启动截图 `/private/tmp/ApiRelay-v11311-clean22-iphone-state.png` 显示设置页正常打开，但截取位置还未到购买区域。前者确认真机当前可见恢复反馈；截图不证明一次新的免费态冷恢复，也不证明退款已发生。
- 产品负责人明确授权仅清除**当前新 Sandbox 测试账号**的测试购买历史后，App Store Connect「用户和访问 → 沙盒」只读确认列表里仅有目标账号（1 个），勾选该账号并执行“清除购买历史记录”；Apple 确认页说明删除的是该测试员的沙盒购买、正式 App Store 购买不受影响。执行按钮进入加载态，随后确认页关闭、账号仍在列表。未删除测试账号，未改其他账户或 App 数据。此操作后的设备 StoreKit 缓存可能仍有旧交易；已请产品负责人在 iPhone 和 iPad 分别退出、重新登录**仅 Sandbox 账号**，冷启动 App 后先核对是否都回到免费态。在两台设备确认前，不把清除操作记作“免费态已通过”，也不进行下一笔购买。
- 产品负责人完成上述两台设备的 Sandbox 退出/重新登录及 App 冷启动后，明确反馈**两台仍显示已购**。停止让用户重复操作。代码复核显示正式 `AppEnvironment` 构建的 `EntitlementService` 未注入测试放行参数；设置页在 `.task` 和回前台时调用 `currentTier()`，后者取 `Transaction.currentEntitlements` 的已验签交易，不使用本地 `EntitlementSnapshot` 授权；无生产路径调用 `debugOverride`。因此此轮不能归咎于本地权益快照残留。
- 为区分 StoreKit 交易与 UI 旧状态，曾给 `EntitlementService.tierFromStoreKit()` 暂加仅 DEBUG 的匿名环境/日期日志，开发签名构建 `1.0.1(23)` 保留数据覆盖到 iPhone 并独立启动。**2026-09-25 19:01 本机时间**，`Transaction.currentEntitlements` 两次返回同一产品、购买时间 **2026-09-25 04:18:02 UTC** 的已验签 `.sandbox` 买断；`AppTransaction` 环境也为 `.sandbox`，`revocationDate == nil`，规则返回 `owned`。这是清除历史和设备重登之后的直接运行证据；未记录交易 ID，故只确认产品与购买时间相同，仍不能单凭 StoreKit API 核实该交易属于哪一个邮箱，也不能断言 Apple 清除服务是否已完全传播。临时日志已从源码移除，iPhone 已保留数据恢复干净 `1.0.1(22)` 且重新启动，`devicectl` 复核构建号为 22；iPad 此时未连接，未再次覆盖。
- 一次追加完整单元测试误用了 `CODE_SIGNING_ALLOWED=NO`，结果包 `/private/tmp/ApiRelay-v11311-clean22-all-unit.xcresult` 为 **493 通过、115 失败、10 跳过**；多数失败是模拟器钥匙串 `-34018` / 材料不可读，StoreKit 测试为 `notEntitled`，伴随 600 秒诊断超时。这次结果**不能算通过，也不能当作产品回归**；先前已签名环境的 618/618 和本轮 iPhone/iPad 购买 UI 各 7/7 是各自独立的既有证据，不能用它们抹掉本次失误。后续若需重跑完整套，必须用签名环境。

历史续记此处曾记“写入状态：进行中”；2026-09-28 当前已停止写入，实际结果及阻塞以页首最新节为准。

## 本轮架构对照与收敛结论

- 对照 Apple [StoreKit `currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements)、[`Transaction.updates`](https://developer.apple.com/documentation/storekit/transaction/updates) 和 [`AppStore.sync()`](https://developer.apple.com/documentation/storekit/appstore/sync%28%29)：现有代码用已验签当前交易决定权限，启动监听异步交易，用户显式点“恢复购买”才调用 `sync()`，本地快照仅作观测。这条主链符合 Apple 提供的原生架构；当前证据不支持因“清除后仍已购”而更换整套购买 SDK、用本地布尔值强制覆盖 StoreKit，或在启动时自动弹 Apple 登录。RevenueCat 等成熟 SDK 还引入自己的后端与身份/缓存状态机，换 SDK 也不能替 Apple 清掉其仍返回的有效 Sandbox 交易。
- 这次观测只证明**设备仍收到有效交易**，没有交易账户邮箱或 App Store Connect 清除完成状态，因此不能把根因定为“Apple 服务器故障”或“用户登错号”。同样，系统退款页在两台设备“无法连接”，只能定为真实退款链路阻塞，不代表本地退款撤权逻辑已通过。
- 下一次不再重复让产品负责人退出登录或点购买。若需恢复真实 Sandbox 从免费开始的验收，先取得一个可核对的**免费态基线**：等待 Apple 清除完成后，由匿名 StoreKit 诊断确认 `currentEntitlements` 为空，或经产品负责人另行同意用全新且未购买的 Sandbox 测试别名；在此之前禁止把当前“已购”状态当作新购买成功。新账号不是代码架构修复，只是隔离测试数据的手段，不应强迫产品负责人反复创建。
- 若同一测试账号在 Apple 文档所述清除和重登后仍持续返回同一未撤销交易，可向 Apple Developer Support 提交复现：开发签名 `com.apirelay.ApiRelay`、iOS/iPadOS 两台、清除历史的 App Store Connect 页面操作、购买日期 `2026-09-25 04:18:02 UTC`、之后设备仍读到 `.sandbox` 未撤销交易；两台退款页“无法连接”是相关现象。向外提交时剔除个人邮箱、设备标识和密钥数据；本轮后续提交情况见下文案例 ID。

## 单账号、免反复切换的后续验收规则

- 产品负责人只保留现有一个 Sandbox 测试账号，iPhone/iPad 不再为了本包反复退出、重新登录或删除 App。没有明确的新证据或单独授权，不再清除同一账号的购买历史，不创建别名账号。
- 将可确定重置测试状态的“免费→购买、用户取消、待批准、批准/拒绝、退款撤权”留在**隔离模拟器的 Xcode StoreKit 测试**；其交易是 `.xcode`，只证明应用状态机和配额逻辑，不能冒称真实 Sandbox。现有 signed 单元与购买 UI fixture 是此轨道的证据；需要补测时使用签名测试构建，避免再次出现钥匙串 `-34018`。
- 真机只运行 StoreKit Configuration = None 的开发签名包，核对现有 Sandbox 买断、跨设备显示/恢复和实际产品元数据；不得从原 `v1.13.9` Xcode 工程运行到同一设备而重新注入 `.xcode` 会话。真实 Sandbox 免费态购买与退款撤权仍保持“未通过/受阻”，不把本地测试结论覆盖到它们。
- 对 Apple 侧仍返回有效交易以及系统退款表单“无法连接”，先以既有日志、购买时间和截图向 Apple 的[开发者支持入口](https://developer.apple.com/contact/)反馈；仅在 Apple 明确给出操作建议或设备交易状态有新证据时重测一次，禁止让产品负责人以账号切换作为常规排障手段。Apple 官方的[测试阶段矩阵](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)明确区分 Xcode 本地与真实 Sandbox，且 Ask to Buy 批准/拒绝只可在 Xcode 本地测试。
- 2026-09-25 用户授权代发 Apple 支持请求。代码级支持表单因没有独立精简示例工程而不适用；改用 Apple Developer「联系我们 → 开发与技术 → 有关开发或技术的其他疑问 → 电子邮件」提交。内容只含 Bundle ID、商品 ID、清除与重登步骤、`currentEntitlements` 仍返回已验签且未撤销的 Sandbox 交易，以及退款原生页面两机“Cannot Connect”；未发送测试账号邮箱、密码、设备 UDID、密钥内容或原始日志。提交后的页面明确显示“感谢你与我们联系”，案例 ID **`102975484910`**，Apple 将邮件回复。此为支持请求，不是 Sandbox 验收通过，也不改变本分支关账状态。
