import Foundation

// MARK: - Upstream account

struct UpstreamAccountDTO: Identifiable, Sendable {
    let id: UUID
    let platform: String
    let customPlatformName: String?
    let displayName: String
    let customBaseURL: String?
    let hasManagementCredential: Bool
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Int
    let deletedAt: Date?
    let purgeAfter: Date?
}

struct UpstreamAccountDraft: Sendable {
    var platform: String
    var customPlatformName: String?
    var displayName: String
    var customBaseURL: String?
    var sortOrder: Int = 0
}

struct UpstreamAccountPatch: Sendable {
    var customPlatformName: String? = nil
    var displayName: String? = nil
    var customBaseURL: String? = nil
    var hasManagementCredential: Bool? = nil
    var sortOrder: Int? = nil
}

// MARK: - Consumer tool

struct ConsumerToolDTO: Identifiable, Sendable {
    let id: UUID
    let name: String
    let iconSymbol: String?
    let isPreset: Bool
    let isHidden: Bool
    let createdAt: Date
    let sortOrder: Int
    let deletedAt: Date?
    let purgeAfter: Date?
}

struct ConsumerToolDraft: Sendable {
    var name: String
    var iconSymbol: String?
    var isPreset: Bool = false
    var sortOrder: Int = 0
}

struct ConsumerToolPatch: Sendable {
    var name: String? = nil
    var iconSymbol: String? = nil
    var isHidden: Bool? = nil
    var sortOrder: Int? = nil
}

// MARK: - Key record persistence helpers

struct KeyRecordDraft: Sendable {
    var accountId: UUID
    var displayName: String
    var maskedHint: String?
    var origin: KeyOrigin = .manualEntry
    var providerKeyRef: String?
    var spendLimit: Decimal?
    var notes: String?
    var secretLength: Int?
}

typealias KeyDraft = KeyRecordDraft

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
}

typealias KeyPatch = KeyRecordPatch

// MARK: - Entitlement snapshot

struct EntitlementSnapshotDTO: Sendable {
    let id: UUID
    let tier: EntitlementTier
    let source: String
    let updatedAt: Date
}
