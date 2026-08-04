# Tasks: V1 — 密钥保险库

**Branch**: `001-key-vault` | **Date**: 2026-08-04
**Input**: [ROADMAP.md](../ROADMAP.md) · [plan.md](./plan.md) · [spec.md](./spec.md) · [data-model.md](./data-model.md) · [contracts/](./contracts/)

## 本文只拆解 V1

**V1 范围**：密钥保管、身份门闩取出、剪贴板分发、使用方指派、双视角列表、免费/买断、
加密备份、设置、Mac Catalyst。

**V1 的决定性边界：完全不联网调用任何上游平台接口。** 由此 V1 **不含**——
管理凭证、平台适配器、用量与余额刷新、费用估算、通知提醒、App 内签发密钥、关系图。
这些属于 V2（`002-usage-insights`），届时另建 tasks。中转属于 V3。

**V1 界面 MUST NOT 出现 V2/V3 功能的入口**，避免用户预期落空。

## 约定

- 路径均相对 **Spec Kit 根目录** `ApiRelay/`。
- `[P]` = 可与同批次其他 `[P]` 任务并行（不同文件、无依赖）。
- 每个 Phase 末尾有 **Checkpoint**，未通过不得进入下一 Phase。
- 提交粒度：**按模块**，提交前 `xcodebuild build` 必须通过。

---

## Phase 1: 工程配置（阻塞全部后续工作）

- [x] **T001** 功能分支 `001-key-vault` 已创建并切换。
- [x] **T002** 构建配置：`SUPPORTS_MACCATALYST = YES`；部署目标对齐 **iOS 18.0 / macOS 15.0**（DC-019）；
      Swift 语言模式切到 **Swift 6**；`ENABLE_USER_SELECTED_FILES = readwrite`
      （否则沙盒阻断加密备份写盘）。
- [x] **T002a** **Bundle Identifier 统一为 `com.apirelay.ApiRelay`**（DC-018）：
      现状为 `com.dsx.ApiRelay`，与 Keychain Service / App Group / iCloud 容器前缀不一致。
      **有用户数据后改名等于换 App**，必须在写第一行业务代码前完成；
      同步改 Xcode target、entitlements 引用、以及 Developer Portal 侧登记。
- [x] **T003** 创建单元测试 target `ApiRelayTests`（logic test，无需 Host App），确认 `xcodebuild build` 可编译通过。
- [x] **T004** `ApiRelay/ApiRelay.entitlements`：iCloud container
      **`iCloud.com.apirelay.ApiRelay`**、App Group `group.com.apirelay.shared`、
      `keychain-access-groups`（plan.md A5）。
      **同时在 Apple Developer Portal 创建对应 Container 与 App Group。**
- [x] **T005** `Info.plist`：`NSFaceIDUsageDescription`（**须本地化**）；
      `ITSAppUsesNonExemptEncryption` 按实际情况声明——产品用了 AES-GCM 与 PBKDF2，
      **遗漏此项会在提交阶段被直接阻断**（FR-045）；
      并加入 `PrivacyInfo.xcprivacy`（FR-058，至少声明 `UserDefaults` / `CA92.1`）。
      （`BGTaskSchedulerPermittedIdentifiers` 属 V2，V1 不加。）
- [x] **T005a** **本地化基础设施**（必须在写第一行界面代码之前完成，否则后期返工量极大）：
      - ✅ 已核实工程 `developmentRegion = en`，**只需追加 `zh-Hans` 本地化**，无需迁移。
        （若曾被改为中文，未覆盖语言的用户会看到中文界面——FR-042 的主要风险点，现已排除。）
      - 创建 `Localizable.xcstrings`（String Catalog），约定**语义化 key** 命名规范
        （`{模块}.{场景}.{元素}`，如 `vault.reveal.button`）。
        **MUST NOT 以英文原文作 key**——改文案等于换 key，会静默丢失中文翻译（FR-043）。
      - 建立 Apple 官方译名对照表：Face ID →「面容 ID」，Touch ID →「触控 ID」，
        Keychain →「钥匙串」，Universal Clipboard →「通用剪贴板」。
      - 约定日期/数字/货币一律走 `FormatStyle`，禁止手工拼接。
- [x] **T006** [P] 目录骨架：`App/ UI/{Vault,Settings,Shared} Business/{Vault,System} Data/{Keychain,SwiftData,Local} Shared/`。
      **V1 不创建 `Business/Provider/`、`Business/Insights/`、`Data/Network/`。**
- [x] **T007** [P] `Shared/ApiRelayError.swift`：按 contracts §1 定义全部 case。
      V2/V3 相关的 case 一次性定义好（避免日后改动共享类型），V1 只是用不到。
      注：Swift 6 MainActor 隔离导致 `Equatable` 暂未添加，标记 TODO Phase 2。
- [x] **T008** [P] `Shared/DiagnosticsReporting.swift`：诊断上报 hook 点。
      **MUST 内置明文过滤，禁止任何凭证进入上报内容。**
- [x] **T009** [P] `Shared/DTOs/`：按 contracts §2 定义全部 DTO 与枚举（含 `KeyHealthDTO` /
      `KeyHealthState`、`KeyOrigin`、`KeyLifecycle`、`EntitlementTier`、`PreferencesDTO` /
      `PreferencesPatch`、`AutomatedSecretPurpose`、`BackupPurpose`、`KeychainService`（含
      **`masterpw`**）等）。同 T007，一次性定义完整。
- [x] **T009a** [P] `Business/Vault/KeyHealthServing.swift`：**仅协议文件**（contracts §3.1a），
      V1 不写实现类、不注入 UI（DC-028）。同步在 `KeyVaultServing` 声明
      `readSecretForAutomatedUse` 签名。

**Checkpoint 1**：工程可构建、可跑空测试，Catalyst target 可启动。

---

## Phase 2: Data 层（阻塞全部用户故事）

### Keychain

- [ ] **T010** `Data/Keychain/KeychainStore.swift`：实现 `KeychainStoring`，声明为 **`actor`**
      （工程默认 MainActor 隔离，不显式声明会拖到主线程）。
      Service 分三类：`keys`（WhenUnlocked + synchronizable）、`admin`（AfterFirstUnlock +
      synchronizable，V1 不用但一次性定义）、`masterpw`（WhenUnlockedThisDeviceOnly + **不同步**）。
      **⚠️ MUST NOT 设置 `kSecAttrAccessControl`——它与 `kSecAttrSynchronizable` 互斥并返回
      `errSecParam`。这是本项目最容易被违反的一条约束。**
- [ ] **T011** [P] `ApiRelayTests/KeychainStoreTests.swift`：覆盖 save/read/delete/listAccounts；
      **专项断言：同时设置 ACL 与 synchronizable 会失败**——把这条互斥关系固化为测试，防止回归。

### SwiftData

- [ ] **T012** `Data/SwiftData/Models/`：按 data-model §3 定义**全部十个实体**——
      `UpstreamAccount`、`APIKeyRecord`、`ConsumerTool`、**`KeyAssignment`（多对多中间表）**、
      `UsageSnapshot`、`BalanceSnapshot`、`PricingRule`、`UserPreferences`、
      **`DevicePreferences`（local，不同步）**、`EntitlementSnapshot`
      （用量相关实体仅 V2 写入，但一次性建好）。
      **理由**：CloudKit schema 一次性部署到生产更稳妥，V2 无需再动 schema；
      `DevicePreferences` 与 `UserPreferences` 拆开是 FR-060 / DC-021 的结构性前提。
      **全部同步属性 MUST optional 或带默认值**（CloudKit 约束）。
      **⚠️ `APIKeyRecord` MUST NOT 有 `consumerToolId` 字段**——指派是多对多，走 `KeyAssignment`。
      **⚠️ `appearance` / `defaultGrouping` MUST NOT 放进 `UserPreferences`**——它们属于 `DevicePreferences`。
- [ ] **T013** `Data/SwiftData/Schema.swift`：`synced`（CloudKit private DB，容器
      `iCloud.com.apirelay.ApiRelay`）+ `local`（`EntitlementSnapshot` + **`DevicePreferences`**，
      `cloudKitDatabase: .none`）双 `ModelConfiguration`，加 `SchemaMigrationPlan` 骨架（v1）。
- [ ] **T014** [P] `Data/SwiftData/Repositories/`：V1 所需的 Repository
      （`UpstreamAccount`、`APIKeyRecord`、`ConsumerTool`、`KeyAssignment`、`UserPreferences`、
      **`DevicePreferences`**、`EntitlementSnapshot`）。`KeyAssignment` 的读取 MUST 按
      `(keyId, consumerToolId)` 去重（CloudKit 无唯一约束，同步竞态会产生重复行）。
      **MUST NOT 向上层泄露 `ModelContext`**（宪法 I）。
- [ ] **T014a** [P] `Business/Vault/PresetCatalog.swift`：两类预置清单作为**内置常量**——
      上游平台（OpenAI、Claude、Google、OpenRouter、DeepSeek、阿里百炼、火山引擎、硅基流动）
      与使用方工具（CL-003 定稿）。
      **MUST NOT 持久化为用户数据**；应用更新扩充清单时 MUST NOT 覆盖或删除用户自建项（FR-007a）。
- [ ] **T014b** **CloudKit Production schema 部署**（FR-063 / DC-027，**硬门槛**）：
      在 CloudKit Dashboard 将 Development schema **Deploy Schema to Production**；
      按 data-model §7.1 逐项核对 Production 侧全部 record types 与预留字段
      （尤其 `APIKeyRecord.healthState` / `lastCheckedAt` / `lastCheckNote`）。
      **仅 Development 可见不算通过。** 将核对结果记入 PR / 提交说明。

**Checkpoint 2**：Keychain 读写在真机通过（含 iCloud 钥匙串开启态）；SwiftData 容器可初始化；
**CloudKit Dashboard → Production 侧**可见 §7.1 全部 record types（T014b）；
`xcodebuild test` 全绿。**未完成 T014b MUST NOT 进入 Phase 3。**

---

## Phase 3: US1 — 保管与取出密钥（V1 的最小可用范围）

### 门闩（四档）

- [ ] **T015** `Business/Vault/RevealGateServing.swift` + `RevealGate.swift`：按 contracts §3.2 实现。
      四档 `RevealPolicy`：`biometricOrPasscode`（`LAPolicy.deviceOwnerAuthentication`）、
      `biometricOnly`（`...WithBiometrics`）、`masterPassword`、`none`。
      `availableBiometry()` 返回 faceID / touchID / none。
      **MUST NOT 跨操作缓存确认结果。**
- [ ] **T016** `Business/System/MasterPasswordService.swift`：`CommonCrypto` 的
      `CCKeyDerivationPBKDF` + SHA256，随机 16 字节 salt，迭代次数校准到约 100ms；
      校验用**恒定时间比较**。存 Keychain `masterpw` Service，**不同步**（FR-038）。
      **主密码仅用于门闩校验，MUST NOT 用于加密任何数据**（research §1.2）。
- [ ] **T017** 主密码的设置、修改与**重置路径**：经生物识别或设备密码确认后可重置（FR-037）。
      设置界面 MUST 明确告知该重置路径存在——**主密码的实际强度不高于设备密码，
      MUST NOT 让用户误以为它不可绕过**（宪法 IX）。
- [ ] **T018** [P] `ApiRelayTests/RevealGateTests.swift`：`policy == .none` 时不调用 `LAContext`；
      无生物识别设备上 `biometricOnly` 返回 `biometryUnavailable`；未设主密码时
      `masterPassword` 档不可用。
- [ ] **T019** [P] `ApiRelayTests/MasterPasswordServiceTests.swift`：正确/错误口令的校验结果；
      salt 每次设置都不同；派生结果不可逆；重置后旧口令失效。

### 剪贴板

- [ ] **T020** `Business/Vault/ClipboardServing.swift` + `SecureClipboard.swift`：
      `UIPasteboard` + `.expirationDate` + `.localOnly`。
      `clearIfStillOurs()` 兜底清除 **MUST 先校验剪贴板内容仍是本产品写入的那一份**，
      否则会误清用户后续复制的内容（FR-005）。

### 保管服务

- [ ] **T021** `Business/Vault/KeyVaultServing.swift`：按 contracts §3.1 定义 protocol
      （含 `readSecretForAutomatedUse`；T009a 若已建则对齐签名）。
      V2 相关方法（`issueKey` 等）不在本 protocol 内，属 `ProviderKeyServing`。
- [ ] **T022** `Business/Vault/KeyVaultService.swift`：账号与密钥 CRUD；
      **`revealSecret` 与 `copySecretToClipboard` 是面向用户取出明文的唯一入口，
      内部串联门闩→Keychain→剪贴板**，UI 层不得自行拼装这三步。
      `readSecretForAutomatedUse` MUST NOT 调用门闩；V1 可先实现为读取 Keychain 或
      明确抛「V2 才启用」，但签名必须存在。
- [ ] **T023** 免费额度校验：`remainingFreeQuota()` 与 `createKey` 前置检查，
      超限抛 `quotaExceededFreeTier(limit: 3)`（FR-026）。
- [ ] **T024** 回收站删除与级联（FR-006 / DC-029）：`deleteKey` = `softDeleted` + 写
      `deletedAt` / `purgeAfter(=+30天)` + **保留 Keychain** + **保留 KeyAssignment**；
      删除账号级联将其下密钥移入回收站。`restoreKey` / `permanentlyDeleteKey` /
      `recentlyDeletedKeys` / `purgeExpiredDeletedKeys` 按 contracts §3.1。
      进入回收站 / 恢复 / 立即删除 MUST 经 `confirmMandatory`。
- [ ] **T024a** 「最近删除」UI：列表展示剩余天数；恢复 / 立即删除；入口放在设置或保险库
      次级页面。主列表 MUST NOT 出现回收站密钥。
- [ ] **T025** 启动时巡检：① 孤儿（元信息有而 Keychain 无 → `secretAvailable = false`；
      Keychain 有而元信息无 → 提示）；② **`purgeExpiredDeletedKeys()`** 永久清除到期项。
- [ ] **T026** [P] `ApiRelayTests/KeyVaultServiceTests.swift`：额度边界（第 3 把成功 / 第 4 把被拒 /
      移入回收站后可再建）、`revealSecret` 必经门闩、**回收站期间 Keychain 仍在**、
      恢复后可复制、永久清除后 Keychain 已移除、`purgeAfter` 过期后被清理。

### UI

- [ ] **T027** `UI/Vault/`：平台分组的密钥列表，**只显示掩码**；`secretAvailable == false`
      时显示「本机暂无明文」状态（FR-002、FR-033）。
- [ ] **T028** 账号与密钥的新建/编辑表单，含名称校验与掩码生成
      （`maskedHint` **MUST NOT 存足以还原明文的内容**）。
- [ ] **T028a** **密钥录入正确性**（FR-056、FR-057 / SC-012）：
      - 密钥输入控件 MUST 关闭自动更正、自动大写、智能标点/智能引号。
      - 保存前去除首尾空白；含空格/制表符/换行 MUST 拒绝并说明原因。
      - 长度明显异常时提醒但 MUST NOT 阻止保存。
      - 同一上游账号下已存在**末 4 位与 `secretLength` 都相同**的密钥时，提示可能重复并指出是哪一条，
        用户确认后才继续。**MUST NOT** 存储明文哈希或任何派生物（宪法 VII）。
      - 单测或手工验收覆盖 SC-012（智能标点环境粘贴含 `-` 的密钥）。
- [ ] **T029** 「查看明文」与「复制」接入 `KeyVaultServing`；复制成功后展示剩余清除时间；
      明文 **MUST NOT 存为 `@Published`**（宪法 VII）。
- [ ] **T030** 额度超限时的引导界面（说明「免费版最多 3 把」+ 解锁入口）。
- [ ] **T031** 主密码输入界面（作为门闩的一档）与设置/修改/重置流程界面。

**Checkpoint 3（V1 已具备独立产品价值）**：能录入、掩码展示、按四档中任一方式验证后查看/复制、
剪贴板 2 分钟后自动清除（含杀死 App 后仍生效）、免费 3 把上限生效。
按 [quickstart.md](./quickstart.md) §1 全部条目验收，含两台真机的同步与通用剪贴板验证。

---

## Phase 4: US2 — 指派使用方与双视角

> **V1 的双视角只做「密钥列表的分组」，不做用量聚合**——用量属 V2。
> 但**分组语义必须一次做对**，因为 V2 的用量汇总直接建在它之上。

- [ ] **T032** `ConsumerTool` 的 CRUD，基于 T014a 的预置清单。
      预置项 MUST 可重命名或隐藏（`isHidden`），**MUST NOT 可物理删除**；用户自建项可删除。
- [ ] **T033** 指派的增删：`addAssignment` / `removeAssignment` / `assignmentKind`（contracts §3.1）。
      **一把密钥可同时指派给多个工具**（FR-007）。取消对某工具的指派 MUST NOT 影响其他指派。
      删除使用方 **MUST NOT 级联删除密钥**，只删除指向它的 `KeyAssignment` 行；
      仅被它指派的密钥回到「未分配」，同时指派给其他工具的密钥保持已分配（data-model §9）。
- [ ] **T034** 分组查询：`byPlatform` 与 `byConsumer` **走同一个分组函数**，仅分组键与归集规则不同。
      归集规则按 `AssignmentKind`：`unassigned` → 「未分配」；`exclusive` → 该工具；
      **`shared`（≥2 个工具）→ 「共享密钥」独立小计**。
      **⚠️ 列表视图 MAY 让共享密钥同时出现在多个工具下，但计数 MUST 只计一次**——
      这是 V2 汇总自洽（SC-005、FR-008a）的结构性前提，
      **MUST NOT 为两个视角各写一份逻辑**。
- [ ] **T035** [P] `ApiRelayTests/GroupingTests.swift`：
      **专项断言：一把密钥指派给 2 个工具时，`byConsumer` 各组去重后的密钥总数
      等于 `byPlatform` 的总数**（即共享密钥只被计一次）；未指派项归入「未分配」而非丢失；
      `KeyAssignment` 存在重复行时读取结果仍正确去重。
- [ ] **T036** `UI/Vault/` 视角切换（按平台 / 按使用方），展开可见其下密钥（FR-008）。
      共享密钥在界面上 MUST 有明确标记（如「被 2 个工具共用」）。
- [ ] **T037** 使用方管理界面（新建、重命名、图标、排序、隐藏/删除 + 影响说明）。
- [ ] **T037a** 自定义**上游平台**的添加界面：平台名称 + 自定义接入地址（FR-007a）。
      自定义平台的能力矩阵默认全部不支持，V1 只需保管功能故无影响。

**Checkpoint 4**：两个视角可切换、共享密钥不重复计数、删除使用方不丢密钥、
两类平台都能自定义添加。按 quickstart §2 验收。

---

## Phase 5: US5 — 付费解锁

- [ ] **T038** `Business/System/EntitlementService.swift`：StoreKit 2；
      `Transaction.currentEntitlements` 为真相源，`EntitlementSnapshot` 仅离线兜底；
      监听 `Transaction.updates`（data-model §3.8）。
- [ ] **T039** Debug override 通道（便于 IAP 审核前验收付费逻辑），**MUST 仅在 DEBUG 构建可用**。
- [ ] **T040** `restorePurchases()` 与界面入口——**苹果审核必查项，缺失会被拒**（FR-028）。
- [ ] **T041** 降级策略：超出免费额度的密钥**只读保留，可看可删，不强制清空**，
      且不允许新增（FR-029）。
- [ ] **T042** 付费墙界面：一档买断解锁无限密钥。
      **MUST NOT 出现任何「中转」相关权益**（V3 才有，FR-032）。
- [ ] **T043** [P] `ApiRelayTests/EntitlementServiceTests.swift`：权限推导；
      `tier == .relay` 在 V1 不可达。
- [ ] **T044** StoreKit Configuration 文件，供本地与 CI 测试。
- [ ] **T044a** **内购不可逆配置定稿并落地**（FR-062 / DC-023，写业务代码前完成）：
      - 产品 ID：`com.apirelay.iap.unlimited_keys`（V1 买断）；预留
        `com.apirelay.iap.relay`（V3，**本期不在 App Store Connect 创建、界面不出现**）。
      - **家庭共享：开启**（一旦开启不可关闭）。
      - StoreKit Configuration 与日后 App Store Connect 产品 ID **一字不差**对齐 plan.md A5。
      - 将定稿结果记入 PR / 提交说明。

**Checkpoint 5**：沙盒购买、恢复购买、降级只读三条路径通过；T044a 产品 ID 与家庭共享已登记。
按 quickstart §5 验收。

---

## Phase 6: US6 — 设置与加密备份

- [ ] **T045** `Business/System/PreferencesService.swift`：同时读写
      **`UserPreferences`（synced，安全相关）** 与 **`DevicePreferences`（local，界面相关）**；
      对外经 `PreferencesServing` 聚合为 `PreferencesDTO` / `PreferencesPatch`（contracts §2）。
      变更立即生效并持久化。**外观 / 默认视角 MUST 只写 `DevicePreferences`**（FR-060）。
      单测须覆盖：改外观不触达 CloudKit 同步实体。
- [ ] **T046** `Business/System/SecureBackupService.swift`：CryptoKit AES-GCM 加密导出/导入；
      导出前 MUST 经 `confirmMandatory`（**该门闩不可关闭**）；**仅密文落盘**。
      **⚠️ 格式必须自 V1 起就留两个字段：`purpose`（`fullBackup` / `transfer`）与 `scope`
      （导出了哪些密钥）。** V1 只用 `fullBackup`，但 V2 的加密传递（FR-047）依赖 `transfer`。
      不留这两个字段，V2 就得做破坏性格式升级，已导出的备份将无法被新版本正确识别用途。
- [ ] **T047** App 锁与自动锁定时长；应用切换器遮罩（不泄露密钥列表）。
- [ ] **T048** `UI/Settings/`：按 FR-021 的 **V1 设置项**（打开 App 需身份确认、取出明文的验证方式、
      主密码设置/修改、剪贴板清除时长、禁用通用剪贴板、切换器遮罩、自动锁定、外观、默认视角、
      **清除全部数据**）。
      **FR-021b 的 V2 设置项（刷新间隔、货币汇率、单价规则、三类提醒）本期不做，不显示占位入口。**
      **「取出密钥明文的验证方式」MUST 是单一设置项，同时管辖查看与复制**——
      不得拆成两个开关（宪法 VIII、quickstart §1.3）。
- [ ] **T048a** `Business/System/DataLifecycleServing.swift` + 实现：`eraseAllUserData()`（FR-061）。
      顺序：`confirmMandatory` → 二次确认文案（含「其他设备同步数据也会被清」）→
      清 Keychain 三类 Service → 清 SwiftData 用户实体 → 清本机 RefreshHealth / 设备偏好 /
      EntitlementSnapshot。**MUST NOT** 吊销 StoreKit。流程中建议先加密备份。
- [ ] **T048b** [P] `ApiRelayTests/DataLifecycleTests.swift`：清除后密钥列表为空、Keychain
      无本产品条目；模拟已购态清除后 `restorePurchases` 仍可恢复权益（SC-014）。
- [ ] **T049** 验证方式文案按 `availableBiometry()` 动态显示「Face ID」或「触控 ID」；
      无生物识别设备上 `biometricOnly` 档不可选并说明原因（FR-003a）。
- [ ] **T050** [P] `ApiRelayTests/PreferencesServiceTests.swift`：各项持久化与默认值
      （剪贴板默认 120 秒、`revealPolicy` 默认 `biometricOrPasscode`）；
      **专项：改 `appearance` 只影响 `DevicePreferences`，不写入 `UserPreferences`（SC-013）**。

**Checkpoint 6**：设置项逐项「立即生效 + 重启保持」；清除全部数据路径按 SC-014 验收。
按 quickstart §6 的 V1 行验收。

---

## Phase 7: Mac Catalyst 适配

- [ ] **T051** [P] 窗口尺寸 `defaultSize(900, 700)`、最小 800×600。
- [ ] **T052** [P] 菜单栏 `Commands`：Settings ⌘,、New Key ⌘N。（Refresh ⌘R 属 V2。）
- [ ] **T053** [P] 鼠标交互：列表 hover、右键菜单（复制 / 查看 / 删除）；⌘C 复制**仍须过门闩**。
- [ ] **T054** ⚠️ 真机实测 `UIPasteboard.expirationDate` 在 macOS 剪贴板上的实际行为；
      若与 iOS 不一致，启用应用内 `Timer` 兜底（plan.md A4）。
- [ ] **T055** ⚠️ 在无 Touch ID 的 Mac 上验证 `biometricOnly` 档自动禁用。

**Checkpoint 7**：Mac 上主流程可用，剪贴板与门闩行为已实测确认。

---

## Phase 8: 安全审查与上架准备

- [ ] **T056** 明文泄露全面排查：SwiftData store 文件、CloudKit Dashboard、日志、崩溃报告、
      `maskedHint` 存储值——**逐项确认无明文**（quickstart §7）。
- [ ] **T057** 代码审查 `KeychainStore`：确认**无** `kSecAttrAccessControl`；
      主密码校验材料确为 `ThisDeviceOnly` 且**未同步**。
- [ ] **T058** 文案审查：安全相关文案与商店描述**不得出现**「系统级强制」「无法绕过」等表述；
      主密码处**必须**告知重置路径的存在（宪法 IX、FR-037）。
- [ ] **T059** 风险披露审查：iCloud 钥匙串同步明文、剪贴板写入两处均有明确告知（宪法 VII）。
- [ ] **T059a** **本地化验收**：
      - 全量搜索源码，确认**无硬编码的面向用户字符串**（FR-043）。
      - 系统语言切到英语、简体中文、以及**一个未覆盖的语言（如法语）**分别启动 →
        **期望法语环境下回退到英语而非中文**（这是 FR-042 的核心验收点）。
      - 检查两种语言下的布局，英文通常更长，确认无截断或换行错乱。
      - 确认 Apple 专有名词用官方译名（「面容 ID」而非「面容识别」）。
      - 日期、金额在不同区域设置下格式正确。
      - 用户输入的密钥名、自定义平台名、自定义工具名**未被翻译**（FR-046）。
- [ ] **T059b** 隐私政策与法律文本的**人工双语**版本（英语 + 简体中文），**禁止机翻**（FR-044）。
- [ ] **T060** [P] 无障碍与体验：Dynamic Type、深色模式、VoiceOver 标签（FR-059 / DC-024）。
      掩码位 MUST NOT 被读出完整明文；门闩通过后的明文区 MAY 读出，且 MUST 支持逐字符朗读。
      **安全边界在门闩，不在辅助功能**——禁止一概屏蔽 VoiceOver 读明文。
- [ ] **T061** 按 [quickstart.md](./quickstart.md) 全量走一遍人工验收
      （**跳过 §3、§4 与 §6 中标注为 V2 的条目**）。
- [ ] **T062** V1 合并回 `main` 并打 tag，作为 V2 的基线。

**Checkpoint 8**：安全清单全绿，V1 功能完整可用。

> **V1 不单独上架**（DC-013）。以下**商店侧材料**推迟到 V2 完成后统一执行：
> App Store 元数据与商店描述、隐私问卷、商店截图、提交审核。
> 但 **`PrivacyInfo.xcprivacy` 与加密出口声明是工程文件**（FR-045、FR-058），MUST 在 V1
> 的 T005 完成，MUST NOT 推迟。
> **V1 的付费逻辑（Phase 5）也不因此省略**——它决定数据模型与权益判断，后补会引起返工。

---

## 依赖关系

```text
Phase 1 (配置) → Phase 2 (Data 层)
                    ├→ Phase 3 (US1 保管取出) ──→ Phase 4 (US2 指派双视角)
                    ├→ Phase 5 (US5 付费)
                    └→ Phase 6 (US6 设置备份)
Phase 3..6 → Phase 7 (Catalyst) → Phase 8 (安全与上架)
```

**关键路径**：T010（Keychain）→ T015/T016（门闩与主密码）→ T020（剪贴板）→ T022（保管服务）
→ T029（取出明文 UI）。这条链上任一环出错都会波及全部安全需求。

**可并行的三条支线**：Phase 4（指派）、Phase 5（付费）、Phase 6（设置）在 Phase 3 完成后互不依赖。

---

## V1 明确不做

| 项 | 归属 | 依据 |
|----|------|------|
| 管理类高权限凭证配置 | V2 | FR-012 |
| 四平台适配器、用量与余额刷新 | V2 | FR-014～FR-020 |
| 费用估算与单价规则 | V2 | FR-015、FR-019 |
| 三类本地通知与后台刷新 | V2 | FR-021a、FR-023 |
| App 内签发/作废密钥 | V2 | FR-009～FR-011 |
| 关系图 | V2 | FR-039～FR-041 |
| **加密传递**（把密钥交给他人） | V2 | US9、FR-047～FR-050 |
| **密钥可用性检测**（感叹号 / 手动探活） | V2 | US10、FR-051～FR-055；V1 预留字段 + `KeyHealthServing` 协议（DC-028），不实现、无 UI |
| 中转服务与中转密钥 | V3 | US7 |
| **可撤销的共享**（给他人签发中转密钥） | V3 | US7、DC-016 |
| 团队功能（成员管理、权限、审计） | **永不做** | DC-016 |
| 逐笔调用明细 | V3 | FR-031 |
| 应用内对话/调用窗口 | 永不做 | FR-OUT-001 |
| 与 VS Code 等外部工具集成 | 永不做 | FR-035 |

`KeyOrigin.providerIssued` / `.relayIssued`、`UsageDataSource.relayLedger`、
`EntitlementTier.relay` 等枚举值 **V1 定义但不可达**，用于保证 V2/V3 无破坏性迁移
（data-model §10）。
