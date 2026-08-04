import Foundation
import SwiftData

/// 密钥元信息。明文只在 Keychain；本模型 MUST NOT 含 `consumerToolId`（多对多走 KeyAssignment）。
@Model
final class APIKeyRecord {
    var id: UUID = UUID()
    var accountId: UUID = UUID()
    var displayName: String = ""
    var maskedHint: String?
    var origin: String = KeyOrigin.manualEntry.rawValue
    var providerKeyRef: String?
    var lifecycle: String = KeyLifecycle.active.rawValue
    var spendLimit: Decimal?
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var purgeAfter: Date?
    var lastVerifiedAt: Date?
    /// V1 恒为 `unknown`；字段为 CloudKit Production schema 预留（FR-055）。
    var healthState: String = KeyHealthState.unknown.rawValue
    var lastCheckedAt: Date?
    var lastCheckNote: String?
    var secretLength: Int?

    init(
        id: UUID = UUID(),
        accountId: UUID,
        displayName: String,
        maskedHint: String? = nil,
        origin: KeyOrigin = .manualEntry,
        providerKeyRef: String? = nil,
        lifecycle: KeyLifecycle = .active,
        spendLimit: Decimal? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil,
        lastVerifiedAt: Date? = nil,
        healthState: KeyHealthState = .unknown,
        lastCheckedAt: Date? = nil,
        lastCheckNote: String? = nil,
        secretLength: Int? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.displayName = displayName
        self.maskedHint = maskedHint
        self.origin = origin.rawValue
        self.providerKeyRef = providerKeyRef
        self.lifecycle = lifecycle.rawValue
        self.spendLimit = spendLimit
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
        self.lastVerifiedAt = lastVerifiedAt
        self.healthState = healthState.rawValue
        self.lastCheckedAt = lastCheckedAt
        self.lastCheckNote = lastCheckNote
        self.secretLength = secretLength
    }
}
