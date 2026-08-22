# 模块接口契约

**Feature**: 密钥保管、分发与用量统计（阶段一）
**Date**: 2026-08-04
**依据**: [data-model.md](../data-model.md) · [research.md](../research.md) · Constitution v2.2.0

> 本文定义**跨层与跨模块的稳定契约**。签名为设计意图，实现时可微调命名，但**语义与错误约定不得变更**。
> 宪法第 II 条：模块间仅经本文所列 protocol 通信。

---

## 0. 依赖规则

| 允许 | 禁止 |
|------|------|
| UI → Business protocol | UI → Keychain / URLSession / ModelContext |
| Business → Data protocol | Business → SwiftUI |
| Data → Apple Frameworks | Data → SwiftUI |
| 同层模块经 protocol | 跨模块直接访问 internal 类型 |

**MainActor 注意**：工程设置 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。Data 层的
`KeychainStoring`、`PlatformAdapting` 实现 MUST 显式声明为 `actor` 或 `nonisolated`，
否则 Keychain 与网络会被拖到主线程（宪法 Stability）。

---

## 1. 共享错误类型

```swift
enum ApiRelayError: Error, Equatable {
    // 门闩
    case authenticationFailed          // 生物识别/密码验证失败
    case authenticationCancelled       // 用户取消
    case biometryUnavailable           // 设备无生物识别能力
    // 保管
    case keychainFailure(OSStatus)
    case secretMissingOnDevice         // 元信息存在但 Keychain 无对应条目
    case quotaExceededFreeTier(limit: Int)
    case validationFailed(field: String, reason: String)
    // 平台
    case capabilityUnsupported(platform: String, capability: PlatformCapability)
    case managementCredentialMissing(accountId: UUID)
    case upstreamRejected(status: Int, message: String?)
    case upstreamResponseUnparsable(detail: String)
    case networkUnavailable
    // 两步一致性（FR-010）
    case createdUpstreamButLocalSaveFailed(providerKeyRef: String?, platform: String)
    // 备份
    case backupPassphraseIncorrect
    case backupVersionUnsupported(found: Int, supported: Int)
}
```

**约定**：错误 MUST 显式传递到 UI，MUST NOT 被吞噬（宪法 V）。
`createdUpstreamButLocalSaveFailed` MUST 触发不可忽略的提示，且 MUST NOT 自动回滚平台侧密钥。

---

## 2. DTO

```swift
struct KeyRecordDTO: Identifiable, Sendable {
    let id: UUID
    let accountId: UUID              // → 上游平台账号（API 提供方）
    let consumerToolIds: [UUID]      // → 使用方工具，多对多；空数组 = 未分配
    let displayName: String
    let maskedHint: String?          // CloudKit 遗留；映射恒为 nil，界面 MUST NOT 展示
    let origin: KeyOrigin            // manualEntry(V1) / providerIssued、receivedFromTransfer(V2) / relayIssued(V3)
    let providerKeyRef: String?
    let lifecycle: KeyLifecycle      // active / revokedUpstream / softDeleted
    let health: KeyHealthDTO         // 独立于 lifecycle；V1 恒为 unknown（FR-055）
    let deletedAt: Date?             // 进回收站时间；非 softDeleted 时为 nil
    let purgeAfter: Date?            // 永久清除截止；UI 用以展示剩余天数
    let spendLimit: Decimal?
    let secretAvailable: Bool        // 本机 Keychain 是否有对应明文
    let secretLength: Int?           // 本机读出的长度，仅供 UI 画点；不入库
}

/// 密钥主动检测结果（US10）。与 lifecycle 分立，见 FR-055。
struct KeyHealthDTO: Sendable {
    let state: KeyHealthState        // unknown / valid / invalid / indeterminate
    let lastCheckedAt: Date?         // nil = 从未检测
    let lastCheckNote: String?       // 不可判定时的原因键，供 UI 呈现
}

enum KeyHealthState: String, Sendable {
    case unknown          // 未检测或平台未接入；UI MUST NOT 显示失效标记
    case valid            // 文案限「密钥有效」，禁止说「可用」（FR-054）
    case invalid          // 已失效；列表带感叹号
    case indeterminate    // 429/超时/5xx/断网；保留上一次结论与时间
}

/// 密钥的指派形态，决定它在「按使用方」维度下如何归集（FR-008a）
enum AssignmentKind: Sendable {
    case unassigned              // 无指派 → 归入「未分配」
    case exclusive(UUID)         // 仅 1 个工具 → 全额归入该工具
    case shared([UUID])          // ≥2 个工具 → 归入「共享密钥」，禁止摊分与重复计数
}

struct UsageDTO: Sendable {
    let keyId: UUID
    let granularity: UsageGranularity   // day / week / month / total
    let periodStart: Date
    let inputTokens: Int?               // nil = 平台未提供，禁止以 0 代替
    let outputTokens: Int?
    let totalTokens: Int?
    let reportedCostUSD: Decimal?       // 平台给出
    let estimatedCostUSD: Decimal?      // 本产品估算
    let pricingRuleId: UUID?
    let dataSource: UsageDataSource     // platformAPI / relayLedger(阶段三)
    let fetchedAt: Date
    let capabilityNote: CapabilityNote? // 驱动 FR-016 的能力限制文案
}

struct UsageRollupDTO: Sendable {
    let group: RollupGroup
    let groupTitle: String
    let children: [UsageDTO]
    let inputTokens: Int?               // 子项之和；任一子项未知则整体标记为部分未知
    let outputTokens: Int?
    let reportedCostUSD: Decimal?
    let estimatedCostUSD: Decimal?
    let hasUnknownComponents: Bool      // true 时 UI MUST 标注「含无法统计的项」
}

/// 分组键。`shared` 与 `unassigned` 是两个独立小计项，不是「某个工具」。
enum RollupGroup: Sendable, Hashable {
    case upstreamAccount(UUID)   // 按平台维度
    case consumerTool(UUID)      // 按使用方维度，仅含独占密钥
    case shared                  // 共享密钥小计（FR-008a），MUST NOT 摊分到各工具
    case unassigned              // 未分配小计
}

struct BalanceDTO: Sendable {
    let accountId: UUID
    let currency: String
    let totalBalance: Decimal?
    let grantedBalance: Decimal?
    let toppedUpBalance: Decimal?
    let isSufficient: Bool?
    let fetchedAt: Date
}

enum PlatformCapability: Sendable {
    case issueKeyInApp        // 可在 App 内签发密钥
    case revokeKeyInApp       // 可在 App 内禁用/删除
    case perKeyUsage          // 可按密钥查用量
    case accountBalance       // 可查账户余额
    case spendLimitPerKey     // 可为单密钥设消费上限
}

enum CapabilityNote: Sendable {
    case perKeyUsageUnsupported     // 「该平台不支持按密钥统计」
    case costNotProvidedByPlatform  // 「费用为本产品估算」
    case managementCredentialNeeded // 「需配置管理凭证后可见」
}

// MARK: - 核心枚举（T009 必须一次性定义完整，含 V2/V3 预留 case）

enum KeyOrigin: String, Sendable {
    case manualEntry              // V1：用户录入
    case providerIssued           // V2：App 内签发
    case receivedFromTransfer     // V2：经加密传递导入
    case relayIssued              // V3：中转签发
}

enum KeyLifecycle: String, Sendable {
    case active
    case revokedUpstream
    case softDeleted
}

enum UsageGranularity: String, Sendable {
    case day, week, month, total
}

enum UsageDataSource: String, Sendable {
    case platformAPI
    case relayLedger              // V3
}

enum EntitlementTier: String, Sendable {
    case free
    case unlimitedKeys
    case relay                    // V3；V1/V2 不可达
}

enum GatedFeature: Sendable {
    case createKeyBeyondFreeQuota
    case relay                    // V3
}

/// 聚合后的偏好视图：安全项来自 `UserPreferences`（synced），界面项来自 `DevicePreferences`（local）。
struct PreferencesDTO: Sendable {
    // synced — UserPreferences（FR-060）
    var appLockEnabled: Bool
    var autoLockSeconds: Int
    var revealPolicy: RevealPolicy
    var clipboardClearSeconds: Int
    var clipboardLocalOnly: Bool
    var hideInAppSwitcher: Bool
    // V2 字段：V1 PreferencesService 持久化默认值，Settings UI 不展示（FR-021b）
    var refreshIntervalMinutes: Int
    var displayCurrency: String
    var usdToDisplayRate: Decimal?
    var notifyLowBalance: Bool
    var notifyKeyRevoked: Bool
    var notifyWeeklyDigest: Bool
    var lowBalanceThreshold: Decimal?
    // local — DevicePreferences（FR-060）；MUST NOT 写入 UserPreferences / CloudKit
    var appearance: AppearancePreference
    var defaultGrouping: GroupingMode
    var lastWindowWidth: Double?
    var lastWindowHeight: Double?
    var platformSectionSort: SectionSortPreference
    var consumerSectionSort: SectionSortPreference
}

enum AppearancePreference: String, Sendable {
    case system, light, dark
}

enum GroupingMode: String, Sendable {
    case byPlatform
    case byConsumer
}

/// 局部更新；未设置的字段保持原值。
/// 实现 MUST：`appearance` / `defaultGrouping` / 窗口尺寸 / 默认头像 → `DevicePreferences`；
/// 其余安全相关字段 → `UserPreferences`（FR-060）。
struct PreferencesPatch: Sendable {
    var appLockEnabled: Bool?
    var autoLockSeconds: Int?
    var revealPolicy: RevealPolicy?
    var clipboardClearSeconds: Int?
    var clipboardLocalOnly: Bool?
    var hideInAppSwitcher: Bool?
    var refreshIntervalMinutes: Int?
    var displayCurrency: String?
    var usdToDisplayRate: Decimal?
    var notifyLowBalance: Bool?
    var notifyKeyRevoked: Bool?
    var notifyWeeklyDigest: Bool?
    var lowBalanceThreshold: Decimal?
    var appearance: AppearancePreference?
    var defaultGrouping: GroupingMode?
    var lastWindowWidth: Double?
    var lastWindowHeight: Double?
    var platformSectionSort: SectionSortPreference?
    var consumerSectionSort: SectionSortPreference?
}
```

---

## 3. Business 层协议

### 3.1 KeyVaultServing — 密钥保管与分发（US1、US2）

```swift
protocol KeyVaultServing: Sendable {
    // 元信息
    func accounts() async throws -> [UpstreamAccountDTO]
    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO]
    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID
    func deleteAccount(_ id: UUID) async throws          // 级联软删其下密钥（data-model §9）

    // 密钥
    func createKey(_ draft: KeyDraft, secret: String) async throws -> UUID
    func updateKey(_ id: UUID, patch: KeyPatch) async throws
    /// 移入「最近删除」回收站（保留 Keychain 30 天）。内部先过 confirmMandatory。
    func deleteKey(_ id: UUID) async throws

    // 回收站（FR-006 / DC-029）
    func recentlyDeletedKeys() async throws -> [KeyRecordDTO]
    /// 恢复为 active。内部先过 confirmMandatory。
    func restoreKey(_ id: UUID) async throws
    /// 立即永久清除（毁 Keychain）。内部先过 confirmMandatory。
    func permanentlyDeleteKey(_ id: UUID) async throws
    /// 启动时调用：永久清除 `purgeAfter < now` 的条目。
    func purgeExpiredDeletedKeys() async throws

    // 指派：多对多，增删各自独立
    func addAssignment(keyId: UUID, consumerToolId: UUID) async throws
    func removeAssignment(keyId: UUID, consumerToolId: UUID) async throws
    func assignmentKind(keyId: UUID) async throws -> AssignmentKind

    // 取出明文——面向用户的唯一入口，内部必过门闩；回收站内密钥不可经此复制到主流程
    func revealSecret(keyId: UUID, purpose: RevealPurpose) async throws -> String
    func copySecretToClipboard(keyId: UUID) async throws

    // 配额（不含 softDeleted）
    func remainingFreeQuota() async throws -> Int?       // nil = 无上限（已购）

    /// 自动化路径读取明文（探活 / 自动刷新）。MUST NOT 触发门闩；MUST NOT 被 UI 直接调用。
    /// 显式命名体现宪法 VIII 的门闩例外。V1 可抛 capabilityUnsupported；V2 由 KeyHealthServing 使用。
    /// softDeleted 密钥 MUST 拒绝（探活不覆盖回收站）。
    func readSecretForAutomatedUse(keyId: UUID, purpose: AutomatedSecretPurpose) async throws -> String
}

enum RevealPurpose: Sendable { case display, copy, export }

enum AutomatedSecretPurpose: Sendable {
    case healthCheck                 // US10 探活（V2）
    case automatedRefresh            // 用量刷新读管理凭证的同类例外预留（V2）
}
```

批量入口见 `RecentlyDeletedBatchServing`（FR-006a）：整批一次 `confirmMandatory`；恢复前预检免费额度，超出则整批拒绝；先处理账号（级联其下回收站密钥），再处理未被覆盖的密钥与使用方。

### 3.1b RecentlyDeletedBatchServing — 回收站批量（FR-006a）

```swift
protocol RecentlyDeletedBatchServing: Actor {
    func restore(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome
    func permanentlyDelete(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome
}
```

**契约要点**

- `revealSecret` MUST 在返回前完成门闩（`RevealGateServing`）。UI 层 MUST NOT 直接访问 Keychain。
- `revealSecret` 返回的 `String` 由调用方在使用后立即释放；MUST NOT 存为 `@Published`（宪法 VII）。
- `createKey` MUST 先校验配额（`quotaExceededFreeTier`）再写入；MUST 执行 FR-056 规范化
  （去首尾空白、拒绝空白符）与 FR-057 重复提示（同账号下本机 Keychain 明文完全相同；
  MUST NOT 存明文哈希或末位片段）。该比对读取 MUST NOT 触发门闩。
- `copySecretToClipboard` 内部串联门闩 → Keychain 读取 → `ClipboardServing.write`，
  UI 层 MUST NOT 自行拼装这三步；对 `softDeleted` MUST 拒绝。
- `deleteKey` MUST NOT 删除 Keychain；`permanentlyDeleteKey` / `purgeExpiredDeletedKeys` 才删。
- `readSecretForAutomatedUse` MUST NOT 调用 `RevealGateServing`；UI MUST NOT 持有该入口的引用
  （依赖注入时勿注入给 ViewModel）。

### 3.1a KeyHealthServing — 密钥可用性检测（US10，V2 实现 / V1 预留）

```swift
/// V1：仅定义协议与 DTO，不提供实现、不在 UI 暴露入口（DC-028）。
/// V2：填入实现；检测逻辑见 FR-051～FR-054。
protocol KeyHealthServing: Sendable {
    func check(keyId: UUID) async throws -> KeyHealthDTO
    func checkAll(keyIds: [UUID]) async -> [UUID: KeyHealthResult]
}

enum KeyHealthResult: Sendable {
    case completed(KeyHealthDTO)
    case skippedUnsupported          // 自定义平台等未接入检测
    case skippedCoolingDown          // 冷却期内
}
```

**契约要点**

- 实现 MUST 经 `readSecretForAutomatedUse(..., .healthCheck)` 取明文，MUST NOT 走 `revealSecret`。
- 批量 MUST 串行节流；429/超时/5xx/无网络 → `indeterminate`，MUST NOT 写成 `invalid`（FR-052）。
- 文案口径「密钥有效」而非「可用」（FR-054）。V1 调用方若误调，实现 MUST 不可达或明确失败。

### 3.2 RevealGateServing — 身份确认门闩（FR-003、宪法 VIII）

```swift
protocol RevealGateServing: Sendable {
    /// 按当前 revealPolicy 执行确认。policy == .none 时直接返回成功。
    func confirm(reason: String, policy: RevealPolicy) async throws

    /// 不可关闭的门闩：加密导出、查看/配置管理类凭证。忽略用户 policy 设置。
    func confirmMandatory(reason: String) async throws

    func availableBiometry() -> BiometryKind   // faceID / touchID / none
}

enum RevealPolicy: String, Sendable {
    case biometricOrPasscode   // LAPolicy.deviceOwnerAuthentication
    case biometricOnly         // LAPolicy.deviceOwnerAuthenticationWithBiometrics
    case masterPassword        // 应用层主密码（FR-003 / FR-038）
    case none                  // 不验证（默认）
}
```

**契约要点**

- 单一 `RevealPolicy` **同时管辖查看与复制**；MUST NOT 提供两个独立开关（宪法 VIII）。
- `availableBiometry()` 用于界面文案动态显示「Face ID / 触控 ID」，并在 `.none` 时禁用
  `biometricOnly` 档（FR-003a）。
- 确认结果 MUST NOT 跨操作缓存。
- **自动刷新读取管理类凭证时 MUST NOT 调用本协议**（宪法 VIII、research §7）。

### 3.3 ClipboardServing — 剪贴板（FR-004、FR-005）

```swift
protocol ClipboardServing: Sendable {
    /// 写入并交由系统在 expiresAfter 后清除（UIPasteboard .expirationDate）。
    /// localOnly = true 时阻止通用剪贴板同步。
    func write(_ secret: String, expiresAfter: TimeInterval, localOnly: Bool)

    /// 兜底清除。MUST 先校验剪贴板当前内容仍是本产品写入的那一份。
    func clearIfStillOurs()
}
```

**契约要点**：主机制为系统级 `.expirationDate`（应用被终止仍生效）；应用内 `Timer` 仅作兜底。
兜底清除 MUST NOT 误清用户此后复制的内容（FR-005）。

### 3.4 ProviderKeyServing — 在 App 内签发/作废密钥（US3）

```swift
protocol ProviderKeyServing: Sendable {
    func capabilities(for accountId: UUID) async -> Set<PlatformCapability>

    /// 在平台侧创建密钥并保存到本地保险库。明文仅在创建响应中出现一次。
    func issueKey(accountId: UUID, name: String, spendLimit: Decimal?) async throws -> UUID

    func revokeKey(keyId: UUID) async throws        // 平台侧禁用 + 本地状态同步
    func verifyKeysStillValid(accountId: UUID) async throws -> [UUID: KeyLifecycle]

    func setManagementCredential(accountId: UUID, credential: String) async throws
    func removeManagementCredential(accountId: UUID) async throws
    func hasManagementCredential(accountId: UUID) async -> Bool
}
```

**契约要点**

- `issueKey` 失败模式必须区分：平台侧未创建（可安全重试）vs 平台侧已创建但本地保存失败
  （抛 `createdUpstreamButLocalSaveFailed`，**MUST NOT 回滚平台侧**，FR-010）。
- 平台不支持时 MUST 抛 `capabilityUnsupported`，UI 依据 `capabilities(for:)` **提前禁用**入口
  而非等待失败（FR-011）。
- `setManagementCredential` / 读取凭证明文 MUST 经 `confirmMandatory`（宪法 VIII）。

### 3.5 UsageServing — 用量与余额（US4）

```swift
protocol UsageServing: Sendable {
    func refresh(accountId: UUID?) async -> [UUID: RefreshOutcome]   // nil = 全部账号
    func usage(keyId: UUID, granularity: UsageGranularity, range: DateInterval) async throws -> [UsageDTO]
    func rollup(by grouping: GroupingMode, range: DateInterval) async throws -> [UsageRollupDTO]
    func balance(accountId: UUID) async throws -> BalanceDTO?
    func health(accountId: UUID) async -> AccountHealth
}

enum RefreshOutcome: Sendable {
    case success(fetchedAt: Date)
    case partiallyUnsupported(note: CapabilityNote)
    case failed(ApiRelayError)
}
```

> `GroupingMode` 定义见 §2（与 `PreferencesDTO.defaultGrouping` 共用同一枚举）。

**契约要点**

- `refresh` **按账号返回独立结果**，单账号失败 MUST NOT 抛出整体错误（宪法 V、FR-018）。
- `rollup` 的两种 `GroupingMode` MUST 走同一聚合实现，仅分组键与归集规则不同（SC-005）。
- `byConsumer` 模式下，共享密钥（指派给 ≥2 个工具）MUST 归入 `RollupGroup.shared`，
  **MUST NOT 摊分到各工具、MUST NOT 重复计入每个工具**（FR-008a、宪法 IX）。
  自洽等式：`byConsumer 各组之和（含 shared 与 unassigned）== byPlatform 各组之和`。
- 任一子项 token 未知时，`UsageRollupDTO.hasUnknownComponents` MUST 为 true，
  且汇总 MUST NOT 把未知当 0（宪法 IX）。
- 刷新失败时 MUST 保留上次成功数据，`health()` 提供可读原因与时间戳（FR-017）。

### 3.6 其余协议

```swift
protocol EntitlementServing: Sendable {
    var tier: EntitlementTier { get async }          // free / unlimitedKeys / relay(不可达)
    func canUse(_ feature: GatedFeature) async -> Bool
    func purchaseUnlimitedKeys() async throws
    func restorePurchases() async throws             // FR-028，苹果审核必查
}

protocol PreferencesServing: Sendable {
    func current() async -> PreferencesDTO
    func update(_ patch: PreferencesPatch) async throws
}
```

**`PreferencesServing` 契约要点**：`update` MUST 按 FR-060 分流——安全字段写入
`UserPreferences`（synced），`appearance` / `defaultGrouping` / 窗口尺寸写入
`DevicePreferences`（local）。UI MUST NOT 直接碰两个 SwiftData 实体。

```swift
protocol SecureBackupServing: Sendable {
    /// V1 只调用 purpose == .fullBackup 且 keyIds == nil（全量导出）。
    /// V2 的加密传递（FR-047）复用同一方法，传 .transfer + 指定的 keyIds。
    /// 格式 MUST 自 V1 起就写入 purpose 与 scope，否则 V2 需破坏性升级格式。
    func export(passphrase: String,
                purpose: BackupPurpose,
                keyIds: [UUID]?) async throws -> URL      // 内部先过 confirmMandatory
    func importBackup(from url: URL, passphrase: String) async throws -> ImportSummary
}

protocol DataLifecycleServing: Sendable {
    /// 清除本产品写入的全部用户数据（FR-061）。内部先过 confirmMandatory。
    /// MUST NOT 清除或吊销 StoreKit 权益。
    func eraseAllUserData() async throws
}

protocol CloudSyncServing: Actor {
    func snapshot() async -> CloudSyncStatusDTO
    /// 催元数据：等到本次 CloudKit 导入/导出结束，或确认本机无待传。
    /// 密钥明文经 iCloud 钥匙串同步，本方法 MUST NOT 声称已在对面设备可取出。
    func requestMetadataSync() async -> CloudSyncNowOutcome
}
```

**`CloudSyncServing` 契约要点**：账号状态用 `CKAccountStatus`，MUST NOT 把本机库回充当「已在云同步」。
界面可展示 CloudKit 用户编号供两台设备对照，MUST NOT 声称能显示 Apple ID 邮箱。
「立即同步」成功只表示**本机元数据已提交或无待传**；MUST NOT 等待或伪造钥匙串进度。

```swift
enum BackupPurpose: String, Sendable {
    case fullBackup   // V1：自用备份
    case transfer     // V2：交付他人。导入方 MUST 据此展示消费责任与不可撤回的告知
}

protocol RefreshScheduling: Sendable {
    func applyInterval(minutes: Int)     // 0 = 仅手动
    func registerBackgroundTask()        // BGAppRefreshTask，机会性调度
}

protocol NotificationScheduling: Sendable {
    func evaluateAfterRefresh(_ outcomes: [UUID: RefreshOutcome]) async
}
```

**`RefreshScheduling` 契约要点**：前台按 `minutes` 精确执行；后台仅向系统**申请**最小间隔，
MUST NOT 向用户承诺按设定间隔执行（FR-021a）。

---

## 4. Data 层协议

```swift
protocol KeychainStoring: Sendable {          // MUST 为 actor
    func save(_ secret: String, service: KeychainService, account: UUID) throws
    func read(service: KeychainService, account: UUID) throws -> String
    func delete(service: KeychainService, account: UUID) throws
    func listAccounts(service: KeychainService) throws -> [UUID]   // 供孤儿巡检
}

enum KeychainService: Sendable {
    case keys      // WhenUnlocked              + synchronizable；Service = com.apirelay.keychain.keys
    case admin     // AfterFirstUnlock          + synchronizable；Service = com.apirelay.keychain.admin
    case masterpw  // WhenUnlockedThisDeviceOnly + **不同步**；Service = com.apirelay.keychain.masterpw（FR-038）
}

protocol PlatformAdapting: Sendable {         // MUST 为 actor，每平台一实现
    var platform: String { get }
    var capabilities: Set<PlatformCapability> { get }
    func issueKey(_ req: IssueKeyRequest, credential: String) async throws -> IssuedKey
    func revokeKey(ref: String, credential: String) async throws
    func listKeys(credential: String) async throws -> [RemoteKeyInfo]
    func fetchUsage(_ req: UsageRequest, credential: String) async throws -> [UsageDTO]
    func fetchBalance(credential: String) async throws -> BalanceDTO?
}
```

**`KeychainStoring` 契约要点**：

- MUST NOT 设置 `kSecAttrAccessControl`——它与 `kSecAttrSynchronizable` 互斥并返回
  `errSecParam`（research §1）。这是最容易被实现阶段违反的一条。
- `masterpw` MUST 使用 `WhenUnlockedThisDeviceOnly` 且 **MUST NOT** 设置 synchronizable
  （FR-038）；主密码校验材料 MUST NOT 放入 `keys` 或 `admin` Service。
- `masterpw` 的 `account` 参数使用实现内固定的 well-known UUID（singleton），
  而非用户实体 id；`listAccounts(.masterpw)` 至多返回 0 或 1 项。

**`PlatformAdapting` 契约要点**：不支持的能力 MUST 抛 `capabilityUnsupported` 而非返回空数据
（宪法 IX）。响应解析失败 MUST 抛 `upstreamResponseUnparsable` 并被上层隔离（宪法 V）。

各平台的具体 HTTP 约定见 [platform-adapters.md](./platform-adapters.md)。

---

## 5. 阶段三扩展点（本期不实现）

| 扩展点 | 阶段三新增 | 既有契约是否变更 |
|--------|-----------|------------------|
| 凭证来源（FR-030） | `KeyOrigin.relayIssued` 启用 | 否，枚举加值 |
| 用量来源（FR-031） | `UsageDataSource.relayLedger` + 新增逐笔查询方法 | 否，协议扩展（默认实现抛 `capabilityUnsupported`） |
| 权益（FR-032） | `EntitlementTier.relay` 启用 | 否，枚举加值 |

`UsageServing` 的现有方法签名足以承载逐笔明细的聚合结果，故 UI 层在阶段三**无需改动**。
