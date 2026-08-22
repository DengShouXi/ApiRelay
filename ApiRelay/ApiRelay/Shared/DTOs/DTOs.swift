import Foundation

// MARK: - 密钥记录 DTO

struct KeyRecordDTO: Identifiable, Sendable {
    let id: UUID
    let accountId: UUID              // → 上游平台账号（API 提供方）
    let consumerToolIds: [UUID]      // → 使用方工具，多对多；空数组 = 未分配
    let displayName: String
    let maskedHint: String?          // CloudKit 遗留；仓库映射恒为 nil，界面 MUST NOT 展示
    let origin: KeyOrigin            // manualEntry(V1) / providerIssued、receivedFromTransfer(V2) / relayIssued(V3)
    let providerKeyRef: String?
    let lifecycle: KeyLifecycle      // active / revokedUpstream / softDeleted
    let health: KeyHealthDTO         // 独立于 lifecycle；V1 恒为 unknown（FR-055）
    let deletedAt: Date?             // 进回收站时间；非 softDeleted 时为 nil
    let purgeAfter: Date?            // 永久清除截止；UI 用以展示剩余天数
    let spendLimit: Decimal?
    let notes: String?               // 可选备注（非密文）
    /// 本机 Keychain 是否有对应条目。仅由属性查询得出，MUST NOT 由读取明文推导。
    let secretAvailable: Bool
    let sortOrder: Int               // 分区内手动排序；越小越靠前
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

// MARK: - 密钥健康度

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

// MARK: - 指派形态

/// 密钥的指派形态，决定它在「按使用方」维度下如何归集（FR-008a）
enum AssignmentKind: Sendable {
    case unassigned              // 无指派 → 归入「未分配」
    case exclusive(UUID)         // 仅 1 个工具 → 全额归入该工具
    case shared([UUID])          // ≥2 个工具 → 归入「共享密钥」，禁止摊分与重复计数
}

// MARK: - 用量 DTO（V2 写入，V1 定义）

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

// MARK: - 平台能力与注解

enum PlatformCapability: Sendable, Equatable {
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

// MARK: - 核心枚举（一次性定义完整，含 V2/V3 预留 case）

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

// MARK: - 偏好 DTO

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
    var assignPickerFilter: AssignPickerFilter
    var lastWindowWidth: Double?
    var lastWindowHeight: Double?
    /// 按平台：上游账号分区排序（本机，FR-064）。
    var platformSectionSort: SectionSortPreference
    /// 按使用方：使用方分区排序（本机，FR-064）。
    var consumerSectionSort: SectionSortPreference
    /// 本机默认头像（空 = 内置）。MUST NOT 写入 UserPreferences。
    var defaultKeyAvatarSymbol: String?
    var defaultKeyAvatarColor: String?
    var defaultCustomAccountAvatarSymbol: String?
    var defaultCustomAccountAvatarColor: String?
    var defaultCustomToolAvatarSymbol: String?
    var defaultCustomToolAvatarColor: String?
}

enum AppearancePreference: String, Sendable {
    case system, light, dark
}

enum GroupingMode: String, Sendable {
    case byPlatform
    case byConsumer
}

/// 按平台 / 按使用方中间栏的分区排序规则（FR-064）。自定义无方向。
enum SectionSortCriterion: String, Sendable, CaseIterable {
    case name
    case createdAt
    case updatedAt
    case custom
}

struct SectionSortPreference: Sendable, Equatable {
    var criterion: SectionSortCriterion
    /// 名称 / 时间的升序；`custom` 时忽略。
    var ascending: Bool

    nonisolated init(criterion: SectionSortCriterion, ascending: Bool) {
        self.criterion = criterion
        self.ascending = ascending
    }

    nonisolated static let nameAscending = SectionSortPreference(criterion: .name, ascending: true)

    nonisolated var usesDirection: Bool { criterion != .custom }

    nonisolated static func naturalDefault(for criterion: SectionSortCriterion) -> SectionSortPreference {
        switch criterion {
        case .name: return SectionSortPreference(criterion: .name, ascending: true)
        case .createdAt: return SectionSortPreference(criterion: .createdAt, ascending: false)
        case .updatedAt: return SectionSortPreference(criterion: .updatedAt, ascending: false)
        case .custom: return SectionSortPreference(criterion: .custom, ascending: true)
        }
    }

    /// 可见项的 `sortOrder` 有重复时，视为尚未写过自定义顺序。
    nonisolated static func needsCustomSeed(sortOrders: [Int]) -> Bool {
        guard sortOrders.count >= 2 else { return false }
        return Set(sortOrders).count != sortOrders.count
    }

    nonisolated static func parse(criterionRaw: String, ascending: Bool) -> SectionSortPreference {
        let criterion = SectionSortCriterion(rawValue: criterionRaw) ?? .name
        return SectionSortPreference(criterion: criterion, ascending: ascending)
    }
}

/// 「按使用方 → 添加已有密钥」弹窗的候选范围（本机偏好，不同步）。
enum AssignPickerFilter: String, Sendable {
    /// 一钥一用：只列出尚未指派给任何使用方的密钥。
    case unassignedOnly
    /// 一钥多用：列出尚未指派给当前使用方的全部密钥（可已被其他使用方使用）。
    case allowShared
}

/// 局部更新；未设置的字段保持原值。
/// 实现 MUST：`appearance` / `defaultGrouping` / `assignPickerFilter` / 窗口尺寸 / 分区排序 → `DevicePreferences`；
/// 其余安全相关字段 → `UserPreferences`（FR-060）。
struct PreferencesPatch: Sendable {
    var appLockEnabled: Bool? = nil
    var autoLockSeconds: Int? = nil
    var revealPolicy: RevealPolicy? = nil
    var clipboardClearSeconds: Int? = nil
    var clipboardLocalOnly: Bool? = nil
    var hideInAppSwitcher: Bool? = nil
    var refreshIntervalMinutes: Int? = nil
    var displayCurrency: String? = nil
    var usdToDisplayRate: Decimal? = nil
    var notifyLowBalance: Bool? = nil
    var notifyKeyRevoked: Bool? = nil
    var notifyWeeklyDigest: Bool? = nil
    var lowBalanceThreshold: Decimal? = nil
    var appearance: AppearancePreference? = nil
    var defaultGrouping: GroupingMode? = nil
    var assignPickerFilter: AssignPickerFilter? = nil
    var lastWindowWidth: Double? = nil
    var lastWindowHeight: Double? = nil
    var platformSectionSort: SectionSortPreference? = nil
    var consumerSectionSort: SectionSortPreference? = nil
    var defaultKeyAvatarSymbol: String? = nil
    var defaultKeyAvatarColor: String? = nil
    var defaultCustomAccountAvatarSymbol: String? = nil
    var defaultCustomAccountAvatarColor: String? = nil
    var defaultCustomToolAvatarSymbol: String? = nil
    var defaultCustomToolAvatarColor: String? = nil

    nonisolated var writesUserPreferences: Bool {
        appLockEnabled != nil
            || autoLockSeconds != nil
            || revealPolicy != nil
            || clipboardClearSeconds != nil
            || clipboardLocalOnly != nil
            || hideInAppSwitcher != nil
            || refreshIntervalMinutes != nil
            || displayCurrency != nil
            || usdToDisplayRate != nil
            || notifyLowBalance != nil
            || notifyKeyRevoked != nil
            || notifyWeeklyDigest != nil
            || lowBalanceThreshold != nil
    }

    nonisolated var writesDevicePreferences: Bool {
        appearance != nil
            || defaultGrouping != nil
            || assignPickerFilter != nil
            || lastWindowWidth != nil
            || lastWindowHeight != nil
            || platformSectionSort != nil
            || consumerSectionSort != nil
            || defaultKeyAvatarSymbol != nil
            || defaultKeyAvatarColor != nil
            || defaultCustomAccountAvatarSymbol != nil
            || defaultCustomAccountAvatarColor != nil
            || defaultCustomToolAvatarSymbol != nil
            || defaultCustomToolAvatarColor != nil
    }
}

// MARK: - 门闩与剪贴板

enum RevealPolicy: String, Sendable {
    case biometricOrPasscode   // LAPolicy.deviceOwnerAuthentication
    case biometricOnly         // LAPolicy.deviceOwnerAuthenticationWithBiometrics
    case masterPassword        // 应用层主密码（FR-003 / FR-038）
    case none                  // 不验证（默认）
}

enum BiometryKind: Sendable {
    case faceID
    case touchID
    case none
}

enum RevealPurpose: Sendable {
    case display
    case copy
    case export
}

enum AutomatedSecretPurpose: Sendable {
    case healthCheck                 // US10 探活（V2）
    case automatedRefresh            // 用量刷新读管理凭证的同类例外预留（V2）
}

// MARK: - 备份

enum BackupPurpose: String, Sendable {
    case fullBackup   // V1：自用备份
    case transfer     // V2：交付他人。导入方 MUST 据此展示消费责任与不可撤回的告知
}

enum BackupFileProtection: Equatable, Sendable {
    case passphraseProtected
    case unprotected
}

// MARK: - Keychain Service

/// Keychain Service 分类，对应 `KeychainStoring` 的 service 参数。
enum KeychainService: Sendable {
    case keys      // WhenUnlocked + synchronizable；Service = com.apirelay.keychain.keys
    case admin     // AfterFirstUnlock + synchronizable；Service = com.apirelay.keychain.admin
    case masterpw  // WhenUnlockedThisDeviceOnly + 不同步；Service = com.apirelay.keychain.masterpw（FR-038）
    case backuppw  // WhenUnlockedThisDeviceOnly + 不同步；Service = com.apirelay.keychain.backuppw
}

// MARK: - 用量刷新

enum RefreshOutcome: Sendable {
    case success(fetchedAt: Date)
    case partiallyUnsupported(note: CapabilityNote)
    case failed(ApiRelayError)
}

// MARK: - iCloud 同步状态（元数据走 CloudKit；明文走钥匙串，无进度）

enum CloudAccountState: Sendable, Equatable {
    case signedIn
    case signedOut
    case restricted
    case temporarilyUnavailable
    case unknown
}

enum CloudSyncActivity: Sendable, Equatable {
    case idle
    case settingUp
    case exporting
    case importing
}

struct CloudSyncStatusDTO: Sendable, Equatable {
    var account: CloudAccountState
    var cloudKitUserRecordName: String?
    var mirroringEnabled: Bool
    var activity: CloudSyncActivity
    var lastSuccessAt: Date?
    var lastFailureMessage: String?

    static let placeholder = CloudSyncStatusDTO(
        account: .unknown,
        cloudKitUserRecordName: nil,
        mirroringEnabled: false,
        activity: .idle,
        lastSuccessAt: nil,
        lastFailureMessage: nil
    )

    /// 系统不提供 Apple ID 邮箱；编号供两台设备对照是否同一套 iCloud。
    var shortCloudIdentity: String? {
        guard let cloudKitUserRecordName, !cloudKitUserRecordName.isEmpty else { return nil }
        let compact = cloudKitUserRecordName.replacingOccurrences(of: "-", with: "")
        let prefix = compact.prefix(8).uppercased()
        return prefix.isEmpty ? nil : String(prefix)
    }
}

enum CloudSyncNowOutcome: Sendable, Equatable {
    case uploaded(Date)
    case nothingToUpload(lastSuccess: Date?)
    case timedOut
    case unavailable
    case localOnly
    case failed(String)
}
