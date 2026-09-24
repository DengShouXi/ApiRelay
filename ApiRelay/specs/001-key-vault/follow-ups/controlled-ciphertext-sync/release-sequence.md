# Release Sequence: v1.13.9 → v1.13.10 → v1.13.11 → v1.14 → UI 重设计

**Status**: `v1.13.10` 已在 `8e6c22109b9f5851dacb31b96e8915d855b0e0f3` 关账；产品负责人已批准插入独立 `v1.13.11` 购买权益验收。`v1.14` 同步与其后的 UI 重设计仍为 plan-only。

**Purpose**: 固定先后顺序，防止密码热修、结构重构、同步迁移和视觉改版再次混在一个工作树中。

## 1. 最终顺序

| 顺序 | 版本/阶段 | 唯一目标 | 明确禁止 |
| --- | --- | --- | --- |
| 1 | `v1.13.9` | 只完成连续切换、既定 iPad/三平台证据、提交上传、独立远程复核并冻结密码功能 | 不再加入重构、同步或视觉改版 |
| 2 | `v1.13.10` | 不改产品功能；拆分超大文件、统一运行期状态来源、建立真正的 XCUITest 界面自动测试 | 不改认证语义/时序、数据格式、CloudKit/Keychain 架构或视觉设计 |
| 3 | `v1.13.11` | 单独验收 StoreKit 购买权益、恢复购买、状态错误与免费额度；从 `v1.13.10` 关账提交建立独立干净工作树 | 不改密码/认证、同步架构、整体 UI；不整包搬运原 `v1.13.9` 未提交草稿或 Xcode 差异 |
| 4 | `v1.14` 候选 | 单独评审并在另行获批后实施受控密文同步；正式实施只能以最终关账、远端复核通过的 `v1.13.11` 为基线 | 不夹带购买热修、密码热修、通用重构或整体 UI 美化 |
| 5 | 同步状态机和数据契约稳定后 | 单独做 UI/配色/布局/图标重设计 | 不同时改同步协议、认证语义或迁移格式 |

任何一段未关账，后一段的产品实现都不能开始。`v1.13.10` 的结构稳定化不改变 Stage 1 产品范围；`v1.13.11` 只验收购买权益。`v1.14` 的版本归属及 D02–D17 安全/产品选择仍属于 G1 候选决定，不能因插入购买阶段而视为批准。同步计划的只读审查可并行，但不得实施或移动 parked 分支。

### 1.1 v1.13.11 插入决定

- **冲突与证据**：旧顺序及同步草案把 `v1.13.10` 写作 `v1.14` 唯一输入基线；产品负责人后续要求先单独验收购买权益，并逐阶段隔离、测试、记录、上传。先前顺序未留购买权益独立版本。
- **批准**：产品负责人于 2026-09-24 审核完整计划后明确要求“按计划逐步实现相关代码，并且做好检测，做好上传工作”；该计划明确建议并单列 `v1.13.11` 购买权益阶段。
- **采用**：插入独立 `v1.13.11`，其本机起点为 `v1.13.10` closure SHA `8e6c22109b9f5851dacb31b96e8915d855b0e0f3`。`v1.14` 后续实施输入随之改为经独立验收、授权上传及远端复核的 `v1.13.11` closure SHA；该 SHA 现在不存在，不能预填。
- **未采用**：不把原 `v1.13.9` 脏工作树购买草稿合进 `13.10`，不跳过购买验收直接从 `13.10` 开始同步，也不将购买与同步放在同一分支。
- **边界**：这仅批准版本顺序和 `13.11` 购买工作，不批准同步 G1 D01 的产品 V2 归属、D02–D17、安全默认值、真实数据迁移、Production cutover、`main`、tag、Archive 或送审。工作包在 `ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.11-购买权益验收/`，当前状态回写 `ZL01/14`。

### 1.2 v1.13.10 启动决定（历史）

- **批准证据**：产品负责人于 2026-09-24 明确要求“实现下一阶段的代码，完成后测试，进一步修改直至成功”。
- **精确基线**：`v1.13.9` 关账提交 `25fe006896a816475e269e155530c1464cc19304`；启动时本地 `v1.13.9`、`v1` 与远端对应指针一致。
- **隔离方式**：从该基线建立独立 `v1.13.10` 分支和干净 worktree，不携带原工作树的治理实验、Xcode 噪声或原始测试产物。
- **本次授权范围**：执行 S0–S6，并在失败时只修复本阶段引入的回归，直至自动测试与可自动验证的构建门槛通过。
- **后续授权更新**：产品负责人已明确授权在 MAIC-1.3.1 方法提交接入、冻结文件对齐及独立复验通过后，按现有阶段 8 对 `v1.13.10` 做 A/B 提交、推送并按既有上传流程快进 `v1`；这不授权 `main`、tag、Archive/送审或任何 `v1.14` 同步实现。
- **证据边界**：尚欠的系统认证面板、真实 App Switcher、Cmd-Tab、多窗口与 Universal Clipboard 人工矩阵继续作为发布闸门，不冒充自动测试，也不解冻 `v1.13.9` 密码语义。

## 2. v1.13.9 关账条件

1. 密码/身份验证代码保持冻结，只处理可复现且经变更机制确认的 P0/P1 回归；
2. 完成产品负责人指定的本轮冻结范围证据；其余历史全矩阵继续如实登记为发布闸门，不能把历史测试数或单次 A/B 结果扩大成全矩阵，也不以此重开已冻结认证代码；
3. 用户明确授权后按精确范围提交/上传，禁止通配暂存脏工作树；
4. 对远端实际内容做独立复核，确认测试证据、文件范围和远端 SHA 一致；
5. 工作区剩余差异全部有归属，不把本地草稿夹带到下一分支；
6. 更新决定记录、权威文件、`ZL01/14` 和路牌后，才登记“已关账”与 closure SHA。

## 3. v1.13.10 纯结构稳定化

### 3.1 为什么要先做

以下是启动 `v1.13.10` 前的 `v1.13.9` 历史盘点，用来解释当时为何先做结构稳定化；不是 `v1.13.11` 当前文件行数：

| 当时文件 | 当时行数（2026-09-24 启动前盘点） | 候选职责切点 |
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

启动 `v1.13.10` 时，Xcode 工程只有 `ApiRelay` App target 和 `ApiRelayTests` unit-test target，没有 `ApiRelayUITests`。该阶段已新增真正的 UI 测试；以下保留当时的验收要求，不描述当前工程状态：

1. 新建独立 `ApiRelayUITests` XCUITest target；
2. 仅增加稳定 accessibility identifiers 和测试启动配置，不用坐标点击、固定等待或生产 secrets；
3. 以 test-only/in-memory fixture 和可控认证 adapter 覆盖 App 自己的导航与状态机；
4. 首批自动路径至少覆盖：验证方式子页连续切换、应用密码确认取消/成功、锁屏遮挡首帧、Home 后快速重开立即锁、设置提交失败不误显示成功、错误提示不被导航遮住；
5. iPhone、iPad、Mac Catalyst/原生 Mac 分开记录可自动化范围；
6. Face ID/Touch ID/设备密码面板、真实 App Switcher 快照、Cmd-Tab、多窗口焦点和 Universal Clipboard 等系统边界继续保留真机人工矩阵，不能伪称 XCUITest 能稳定代替。

### 3.4 v1.13.10 当时的实施顺序（已完成）

```text
S0  v1.13.9 已关账 → 从 closure SHA 建 v1.13.10
S1  先加 characterization + XCUITest target/fixture/identifiers
S2  写状态 ownership 表与依赖规则，不改行为
S3  机械拆 UI 大文件：一次一个职责、一个可回滚变更单元
S4  机械拆 service/controller：保留 façade，先搬后改
S5  逐项统一状态来源：一次只迁一个 ownership
S6  单元/集成/XCUITest/三端构建 + 本阶段受影响真机边界回归
S7  独立审查；另获用户提交上传授权后，才做远端复核与关账
```

禁止“大爆炸重构”。每一步测试失败只回退该步；不得顺手修 UI、改文案、调锁定时长、改密码语义、改 schema 或开始新同步。

### 3.5 v1.13.10 硬验收

- 用户可见功能、默认值、认证路径、错误语义、数据和本地化文案保持等价；
- Bundle ID、Team ID、Keychain service/access group、iCloud container、SwiftData schema/store path 不变；
- public service protocols 与持久 ID 不在机械拆分中漂移；
- 原有单元/集成测试全绿，新增 XCUITest 不是只启动 App 的空测试；
- 三平台构建与本阶段受影响的关键真机路径通过：iPhone/iPad 验证方式连续切换与 Home 快返立即锁，Mac 失焦锁定/遮挡；更宽的历史全矩阵继续作为发布闸门；
- 每个大文件的职责图、移动映射和回滚提交明确；
- 状态 ownership 检查证明没有第二权威、双计时器或 UI 自行改安全状态；
- 性能、启动、内存与日志脱敏没有回归；
- 独立审查确认“结构改变、产品行为未改变”。

## 4. v1.14 同步的基线

受控密文同步的正式实施只能从最终关账并远端复核通过的 `v1.13.11` closure SHA 开始。`v1.13.11` 本身从 `v1.13.10@8e6c221` 建立，并只处理购买权益；这样同步实施同时继承结构稳定化和购买验收的已核对状态。`v1.13.11` 尚未关账时，不得把当前起点 `8e6c221` 冒充未来同步基线。

v1.14 仍需自己的 G1 产品裁决、权威回写、协议统一冻结、Development/Production shadow、迁移和不可逆 cleanup 闸门；v1.13.10 或 v1.13.11 的完成均不自动授权同步。

## 5. UI 重设计为什么最后

同步阶段会新增 queued/cloud accepted/device acknowledged/conflict/recovery/device management 等用户状态。如果提前重画 UI，信息架构会在同步状态冻结后再次返工。因此 UI 重设计在 v1.14 状态机和错误恢复语义稳定后另立版本，只改视觉系统与信息层级，不同时改认证、同步或迁移协议。
