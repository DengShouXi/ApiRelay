# Release Sequence: v1.13.9 → v1.13.10 → v1.14 → UI 重设计

**Status**: plan-only；本轮不创建/切换分支，不改 Swift/Xcode，不执行迁移

**Purpose**: 固定先后顺序，防止密码热修、结构重构、同步迁移和视觉改版再次混在一个工作树中。

## 1. 最终顺序

| 顺序 | 版本/阶段 | 唯一目标 | 明确禁止 |
| --- | --- | --- | --- |
| 1 | `v1.13.9` | 只完成连续切换、既定 iPad/三平台证据、提交上传、独立远程复核并冻结密码功能 | 不再加入重构、同步或视觉改版 |
| 2 | `v1.13.10` | 不改产品功能；拆分超大文件、统一运行期状态来源、建立真正的 XCUITest 界面自动测试 | 不改认证语义/时序、数据格式、CloudKit/Keychain 架构或视觉设计 |
| 3 | `v1.14` 候选 | 单独实施受控密文同步；以最终关账的 `v1.13.10` 为唯一基线 | 不夹带密码热修、通用重构或整体 UI 美化 |
| 4 | 同步状态机和数据契约稳定后 | 单独做 UI/配色/布局/图标重设计 | 不同时改同步协议、认证语义或迁移格式 |

任何一段未关账，后一段都不能开始。版本号属于 G1 候选决定；若正式 ROADMAP 另有裁决，以权威回写结果为准，但上述职责隔离不变。

## 2. v1.13.9 关账条件

1. 密码/身份验证代码保持冻结，只处理可复现且经变更机制确认的 P0/P1 回归；
2. 完成当前状态中尚未取得的发布证据；不能把历史测试数或单次 A/B 结果扩大成全矩阵；
3. 用户明确授权后按精确范围提交/上传，禁止通配暂存脏工作树；
4. 对远端实际内容做独立复核，确认测试证据、文件范围和远端 SHA 一致；
5. 工作区剩余差异全部有归属，不把本地草稿夹带到下一分支；
6. 更新决定记录、权威文件、`ZL01/14` 和路牌后，才登记“已关账”与 closure SHA。

## 3. v1.13.10 纯结构稳定化

### 3.1 为什么要先做

当前主工程约 33,706 行 Swift，已有多个职责过载文件：

| 当前文件 | 当前行数（2026-09-24 只读盘点） | 候选职责切点 |
| --- | ---: | --- |
| `UI/Vault/VaultHomeView.swift` | 4,595 | 根容器、列表/分组、搜索、编辑 sheet、删除/恢复交互、平台适配 |
| `UI/Settings/SettingsView.swift` | 2,184 | 设置根页、验证方式、隐私/锁定、同步/数据管理与各编辑流程 |
| `Business/Vault/KeyVaultService.swift` | 1,999 | 查询、写命令、删除/恢复、指派、导入协调；公共 protocol 保持不变 |
| `App/AppPrivacyController.swift` | 1,893 | 纯状态 reducer、平台生命周期 adapter、认证协调、遮挡呈现 |
| `UI/Settings/BackupSettingsViews.swift` | 1,373 | 导入、导出、恢复、密码输入等独立页面 |
| `UI/Vault/VaultHomeViewModel.swift` | 1,360 | 列表状态、编辑命令、删除/恢复命令、用户提示映射 |
| `Business/System/SecureBackupService.swift` | 1,072 | 格式/crypto、文件 IO、导入校验、业务提交协调 |
| `Business/System/SessionLockQuerying.swift` | 1,021 | session snapshot/lease、策略变更 token、认证结果 token 等独立协议/实现 |

行数只是风险信号，不是为了追求任意数字而拆文件。每次拆分必须围绕一个可测试职责，并保留原公共 façade/协议，先搬代码再改设计。

### 3.2 唯一状态来源

v1.13.10 要冻结以下 ownership；UI 只能派生显示，不再维护第二份事实：

| 状态 | 唯一权威 | 其他层允许做什么 |
| --- | --- | --- |
| 锁定/解锁/session generation/lease | `AppLockSession` 状态值，由 `AppPrivacyController` 单一 reducer 发布 | query/lease 只能读取同一 generation 的快照，不另存 `isLocked` 真相 |
| 当前认证请求 | `AuthenticationRequestCoordinator` | 页面只持有 request scope/显示状态，不自行决定请求是否仍有效 |
| application/scene/window presence | 平台 adapter 收集原始事实，`WindowPrivacyReducer` 纯函数归并 | UI 不以自己的 scene flag 推翻 reducer |
| 隐私遮挡 | 由 session + presence + preference 的单一派生结果 | 每个窗口只呈现结果，不各自计算策略 |
| 持久安全偏好 | `PreferencesService`/repository 的版本化快照 | 设置页只保留未提交 draft；提交成功后从权威快照刷新 |
| 存储写封锁 | `StorageMutationGate` | 各 service 只申请/验证 capability，不维护独立清除 flag |
| 剪贴板所有权与清理代次 | 单一 clipboard service/coordinator | View 不自行启动第二套 timer 或保存 changeCount |

“统一状态来源”可能改变内部依赖，因此不能和机械拆文件放在同一提交；必须先用 characterization tests 固定行为，再逐个 ownership 迁移并做等价证明。

### 3.3 真正的界面自动测试

当前 Xcode 工程只有 `ApiRelay` App target 和 `ApiRelayTests` unit-test target，没有 `ApiRelayUITests`；现有 XCTest 数量不能代替真实界面自动化。v1.13.10 必须：

1. 新建独立 `ApiRelayUITests` XCUITest target；
2. 仅增加稳定 accessibility identifiers 和测试启动配置，不用坐标点击、固定等待或生产 secrets；
3. 以 test-only/in-memory fixture 和可控认证 adapter 覆盖 App 自己的导航与状态机；
4. 首批自动路径至少覆盖：验证方式子页连续切换、应用密码确认取消/成功、锁屏遮挡首帧、Home 后快速重开立即锁、设置提交失败不误显示成功、错误提示不被导航遮住；
5. iPhone、iPad、Mac Catalyst/原生 Mac 分开记录可自动化范围；
6. Face ID/Touch ID/设备密码面板、真实 App Switcher 快照、Cmd-Tab、多窗口焦点和 Universal Clipboard 等系统边界继续保留真机人工矩阵，不能伪称 XCUITest 能稳定代替。

### 3.4 实施顺序（未来，均需另授权）

```text
S0  v1.13.9 已关账 → 从 closure SHA 建 v1.13.10
S1  先加 characterization + XCUITest target/fixture/identifiers
S2  写状态 ownership 表与依赖规则，不改行为
S3  机械拆 UI 大文件：一次一个职责、一个可回滚提交
S4  机械拆 service/controller：保留 façade，先搬后改
S5  逐项统一状态来源：一次只迁一个 ownership
S6  单元/集成/XCUITest/三端构建 + 真机边界回归
S7  独立审查、用户授权提交上传、远端复核、关账
```

禁止“大爆炸重构”。每一步测试失败只回退该步；不得顺手修 UI、改文案、调锁定时长、改密码语义、改 schema 或开始新同步。

### 3.5 v1.13.10 硬验收

- 用户可见功能、默认值、认证路径、错误语义、数据和本地化文案保持等价；
- Bundle ID、Team ID、Keychain service/access group、iCloud container、SwiftData schema/store path 不变；
- public service protocols 与持久 ID 不在机械拆分中漂移；
- 原有单元/集成测试全绿，新增 XCUITest 不是只启动 App 的空测试；
- 三平台构建与关键真机矩阵通过；
- 每个大文件的职责图、移动映射和回滚提交明确；
- 状态 ownership 检查证明没有第二权威、双计时器或 UI 自行改安全状态；
- 性能、启动、内存与日志脱敏没有回归；
- 独立审查确认“结构改变、产品行为未改变”。

## 4. v1.14 同步的基线

受控密文同步只能从最终关账并远端复核通过的 `v1.13.10` closure SHA 开始。这样同步实现面对的是已经拆清职责、状态 ownership 固定且有真实 UI 回归保护的代码，而不是继续在 4,000 行 View 和 1,800 行隐私控制器中叠加新状态。

v1.14 仍需自己的 G1 产品裁决、权威回写、协议统一冻结、Development/Production shadow、迁移和不可逆 cleanup 闸门；v1.13.10 的完成不自动授权同步。

## 5. UI 重设计为什么最后

同步阶段会新增 queued/cloud accepted/device acknowledged/conflict/recovery/device management 等用户状态。如果提前重画 UI，信息架构会在同步状态冻结后再次返工。因此 UI 重设计在 v1.14 状态机和错误恢复语义稳定后另立版本，只改视觉系统与信息层级，不同时改认证、同步或迁移协议。
