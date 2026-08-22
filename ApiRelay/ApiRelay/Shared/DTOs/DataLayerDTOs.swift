import Foundation

// MARK: - Upstream account

struct UpstreamAccountDTO: Identifiable, Sendable {
    let id: UUID
    let platform: String
    let customPlatformName: String?
    let displayName: String
    let customBaseURL: String?
    let hasManagementCredential: Bool
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Int
    let deletedAt: Date?
    let purgeAfter: Date?
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

struct UpstreamAccountDraft: Sendable {
    var platform: String
    var customPlatformName: String?
    var displayName: String
    var customBaseURL: String?
    var notes: String? = nil
    var sortOrder: Int = 0
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

struct UpstreamAccountPatch: Sendable {
    var platform: String? = nil
    var customPlatformName: String? = nil
    var displayName: String? = nil
    var customBaseURL: String? = nil
    var hasManagementCredential: Bool? = nil
    var notes: String? = nil
    var sortOrder: Int? = nil
    var updatesAvatar: Bool = false
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

// MARK: - Consumer tool

struct ConsumerToolDTO: Identifiable, Sendable {
    let id: UUID
    let name: String
    let iconSymbol: String?
    let isPreset: Bool
    let isHidden: Bool
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Int
    let deletedAt: Date?
    let purgeAfter: Date?
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

struct ConsumerToolDraft: Sendable {
    var name: String
    var iconSymbol: String?
    var isPreset: Bool = false
    var notes: String? = nil
    var sortOrder: Int = 0
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

struct ConsumerToolPatch: Sendable {
    var name: String? = nil
    var iconSymbol: String? = nil
    var isHidden: Bool? = nil
    var notes: String? = nil
    var sortOrder: Int? = nil
    var updatesAvatar: Bool = false
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

// MARK: - Key record persistence helpers

struct KeyRecordDraft: Sendable {
    var accountId: UUID
    var displayName: String
    var maskedHint: String? = nil    // 忽略；插入时恒为 nil
    var origin: KeyOrigin = .manualEntry
    var providerKeyRef: String?
    var spendLimit: Decimal?
    var notes: String?
    var secretLength: Int? = nil     // 忽略；插入时恒为 nil
    var sortOrder: Int = 0
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

typealias KeyDraft = KeyRecordDraft

/// 编辑已有密钥（名称 / 可选换密文 / 备注 / 所属上游账号的平台与显示名）。
struct KeyEditDraft: Sendable {
    var displayName: String
    /// `nil` 或纯空白 → 保留原密文，不读、不写 Keychain。
    var secret: String? = nil
    var acknowledgePossibleDuplicate: Bool = false
    /// 写入备注；空字符串表示清空。
    var notes: String? = nil
    var accountDisplayName: String
    var platform: String
    var customPlatformName: String? = nil
    var customBaseURL: String? = nil
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

struct KeyRecordPatch: Sendable {
    var displayName: String? = nil
    var maskedHint: String? = nil
    var lifecycle: KeyLifecycle? = nil
    var spendLimit: Decimal? = nil
    var notes: String? = nil
    var deletedAt: Date? = nil
    var purgeAfter: Date? = nil
    var healthState: KeyHealthState? = nil
    var lastCheckedAt: Date? = nil
    var lastCheckNote: String? = nil
    var secretLength: Int? = nil
    var sortOrder: Int? = nil
    var updatesAvatar: Bool = false
    var avatarSymbol: String? = nil
    var avatarColor: String? = nil
}

typealias KeyPatch = KeyRecordPatch

// MARK: - Entitlement snapshot

struct EntitlementSnapshotDTO: Sendable {
    let id: UUID
    let tier: EntitlementTier
    let source: String
    let updatedAt: Date
}
