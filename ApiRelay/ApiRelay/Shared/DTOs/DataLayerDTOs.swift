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
}

struct ConsumerToolDraft: Sendable {
    var name: String
    var iconSymbol: String?
    var isPreset: Bool = false
    var sortOrder: Int = 0
}

struct ConsumerToolPatch: Sendable {
    var name: String?
    var iconSymbol: String?
    var isHidden: Bool?
    var sortOrder: Int?
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

struct KeyRecordPatch: Sendable {
    var displayName: String?
    var maskedHint: String?
    var lifecycle: KeyLifecycle?
    var spendLimit: Decimal?
    var notes: String?
    var deletedAt: Date?
    var purgeAfter: Date?
    var healthState: KeyHealthState?
    var lastCheckedAt: Date?
    var lastCheckNote: String?
    var secretLength: Int?
}

// MARK: - Entitlement snapshot

struct EntitlementSnapshotDTO: Sendable {
    let id: UUID
    let tier: EntitlementTier
    let source: String
    let updatedAt: Date
}
