import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Cross-store operations whose rollback cannot be represented by one
/// SwiftData save. The marker phase tells startup recovery whether it must
/// roll back provisional work, finish a committed operation, or only remove a
/// completed tombstone before ordinary storage is reopened.
nonisolated enum CrossStoreTransactionKind: String, Codable, Sendable {
    case createKey
    case backupImport
}

/// Write-ahead transaction state. Recovery rolls back only `.applying`.
/// Once `.commitDecided` is durably visible, recovery may only finish removing
/// the marker; it must never undo the already-committed business operation.
nonisolated enum CrossStoreTransactionPhase: String, Codable, Sendable {
    case applying
    case commitDecided
    /// Durable tombstone written before unlink. If an unlink directory-fsync is
    /// uncertain and this file resurfaces after a crash, recovery only retries
    /// removal; it never replays rollback/finalization.
    case completed
}

/// Ownership proof for one SwiftData row inserted by the transaction.
/// `createdAt` is selected before the repository commit and written both here
/// and into the model, so recovery never deletes a same-id replica imported
/// from another device after the transaction started.
nonisolated struct CrossStoreInsertedRecordPlan: Codable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
}

nonisolated struct CrossStoreKeyRollbackPlan: Codable, Sendable, Equatable {
    let id: UUID
    let accountId: UUID
    let createdAt: Date
}

nonisolated struct CrossStoreAssignmentRollbackPlan: Codable, Sendable, Equatable {
    let keyId: UUID
    let consumerToolId: UUID
    let createdAt: Date
}

nonisolated struct CrossStoreTransactionRecord: Codable, Sendable, Equatable {
    let version: Int
    let transactionId: UUID
    let kind: CrossStoreTransactionKind
    let startedAt: Date
    var phase: CrossStoreTransactionPhase
    var insertedAccounts: [CrossStoreInsertedRecordPlan]
    var insertedTools: [CrossStoreInsertedRecordPlan]
    var insertedKeys: [CrossStoreKeyRollbackPlan]
    var insertedAssignments: [CrossStoreAssignmentRollbackPlan]

    nonisolated init(
        transactionId: UUID = UUID(),
        kind: CrossStoreTransactionKind,
        startedAt: Date = Date(),
        insertedAccounts: [CrossStoreInsertedRecordPlan] = [],
        insertedTools: [CrossStoreInsertedRecordPlan] = [],
        insertedKeys: [CrossStoreKeyRollbackPlan] = [],
        insertedAssignments: [CrossStoreAssignmentRollbackPlan] = []
    ) {
        self.version = 3
        self.transactionId = transactionId
        self.kind = kind
        self.startedAt = startedAt
        self.phase = .applying
        self.insertedAccounts = insertedAccounts
        self.insertedTools = insertedTools
        self.insertedKeys = insertedKeys
        self.insertedAssignments = insertedAssignments
    }

    /// Reject syntactically valid but unsafe/corrupt records before any delete.
    nonisolated func validateForRecovery() throws {
        // Version 2 markers were produced by development builds before the
        // durable commit-decision field existed. Decode them as `.applying` so
        // an interrupted provisional operation is conservatively rolled back.
        guard version == 2 || version == 3 else {
            throw Self.invalid("unsupported_version")
        }
        let maximumPlans = 100_000
        guard insertedAccounts.count <= maximumPlans,
              insertedTools.count <= maximumPlans,
              insertedKeys.count <= maximumPlans,
              insertedAssignments.count <= maximumPlans else {
            throw Self.invalid("plan_limit_exceeded")
        }
        guard Set(insertedAccounts.map(\.id)).count == insertedAccounts.count,
              Set(insertedTools.map(\.id)).count == insertedTools.count,
              Set(insertedKeys.map(\.id)).count == insertedKeys.count else {
            throw Self.invalid("duplicate_record_plan")
        }
        let assignmentIDs = insertedAssignments.map {
            "\($0.keyId.uuidString)|\($0.consumerToolId.uuidString)"
        }
        guard Set(assignmentIDs).count == assignmentIDs.count else {
            throw Self.invalid("duplicate_assignment_plan")
        }
        switch kind {
        case .createKey:
            guard insertedAccounts.isEmpty,
                  insertedTools.isEmpty,
                  insertedAssignments.isEmpty,
                  insertedKeys.count <= 1 else {
                throw Self.invalid("invalid_create_key_shape")
            }
        case .backupImport:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case transactionId
        case kind
        case startedAt
        case phase
        case insertedAccounts
        case insertedTools
        case insertedKeys
        case insertedAssignments
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        transactionId = try values.decode(UUID.self, forKey: .transactionId)
        kind = try values.decode(CrossStoreTransactionKind.self, forKey: .kind)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        phase = try values.decodeIfPresent(
            CrossStoreTransactionPhase.self,
            forKey: .phase
        ) ?? .applying
        insertedAccounts = try values.decode(
            [CrossStoreInsertedRecordPlan].self,
            forKey: .insertedAccounts
        )
        insertedTools = try values.decode(
            [CrossStoreInsertedRecordPlan].self,
            forKey: .insertedTools
        )
        insertedKeys = try values.decode(
            [CrossStoreKeyRollbackPlan].self,
            forKey: .insertedKeys
        )
        insertedAssignments = try values.decode(
            [CrossStoreAssignmentRollbackPlan].self,
            forKey: .insertedAssignments
        )
    }

    private nonisolated static func invalid(_ detail: String) -> ApiRelayError {
        .storageRecoveryFailed(operation: "cross_store_journal_validate", detail: detail)
    }
}

protocol CrossStoreTransactionJournalStoring: Sendable {
    nonisolated func hasPendingTransaction() -> Bool
    nonisolated func load() throws -> CrossStoreTransactionRecord?
    nonisolated func begin(_ kind: CrossStoreTransactionKind) throws -> UUID
    nonisolated func planInsertedAccount(
        _ plan: CrossStoreInsertedRecordPlan,
        transactionId: UUID
    ) throws
    nonisolated func planInsertedTool(
        _ plan: CrossStoreInsertedRecordPlan,
        transactionId: UUID
    ) throws
    nonisolated func planInsertedKey(
        _ plan: CrossStoreKeyRollbackPlan,
        transactionId: UUID
    ) throws
    nonisolated func planInsertedAssignment(
        _ plan: CrossStoreAssignmentRollbackPlan,
        transactionId: UUID
    ) throws
    nonisolated func decideCommit(transactionId: UUID) throws
    nonisolated func clear(transactionId: UUID) throws
    /// An authenticated full erase supersedes rollback and removes the marker
    /// only after all protected stores have been purged.
    nonisolated func discardForCommittedErase(
        authorization: CommittedEraseToken
    ) throws
}

/// All journal objects targeting the same path share one in-process lock. The
/// durable journal also takes an advisory file lock, so a second macOS process
/// cannot pass `begin` concurrently and overwrite the first process's marker.
nonisolated private final class CrossStoreJournalPathLockRegistry: @unchecked Sendable {
    nonisolated static let shared = CrossStoreJournalPathLockRegistry()

    private let registryLock = NSLock()
    private var locks: [String: NSLock] = [:]

    nonisolated func lock(for path: String) -> NSLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[path] { return existing }
        let created = NSLock()
        locks[path] = created
        return created
    }
}

/// fsync + atomic-rename journal for operations spanning SwiftData and
/// Keychain. Every ownership plan is durable inside the repository commit
/// boundary before the corresponding model save.
nonisolated final class DurableCrossStoreTransactionJournal:
    CrossStoreTransactionJournalStoring,
    @unchecked Sendable
{
    private let processLock: NSLock
    private let fileURL: URL
    private let lockFileURL: URL

    nonisolated init(fileURL: URL? = nil) {
        let resolvedFileURL = (fileURL ?? Self.defaultFileURL()).standardizedFileURL
        self.fileURL = resolvedFileURL
        self.lockFileURL = resolvedFileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(resolvedFileURL.lastPathComponent).lock", isDirectory: false)
        self.processLock = CrossStoreJournalPathLockRegistry.shared.lock(
            for: resolvedFileURL.path
        )
    }

    nonisolated func hasPendingTransaction() -> Bool {
        do {
            return try withExclusiveJournalLock {
                FileManager.default.fileExists(atPath: fileURL.path)
            }
        } catch {
            // Failure to inspect the recovery marker must never open storage.
            return true
        }
    }

    nonisolated func load() throws -> CrossStoreTransactionRecord? {
        try withExclusiveJournalLock {
            let record = try readLocked()
            try record?.validateForRecovery()
            return record
        }
    }

    nonisolated func begin(_ kind: CrossStoreTransactionKind) throws -> UUID {
        try withExclusiveJournalLock {
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_journal_begin",
                    detail: "pending_transaction_exists"
                )
            }
            let record = CrossStoreTransactionRecord(kind: kind)
            try writeLocked(record)
            return record.transactionId
        }
    }

    nonisolated func planInsertedAccount(
        _ plan: CrossStoreInsertedRecordPlan,
        transactionId: UUID
    ) throws {
        try update(
            transactionId: transactionId,
            operation: "plan_account",
            requiresApplying: true
        ) { record in
            guard !record.insertedAccounts.contains(where: { $0.id == plan.id }) else { return }
            record.insertedAccounts.append(plan)
        }
    }

    nonisolated func planInsertedTool(
        _ plan: CrossStoreInsertedRecordPlan,
        transactionId: UUID
    ) throws {
        try update(
            transactionId: transactionId,
            operation: "plan_tool",
            requiresApplying: true
        ) { record in
            guard !record.insertedTools.contains(where: { $0.id == plan.id }) else { return }
            record.insertedTools.append(plan)
        }
    }

    nonisolated func planInsertedKey(
        _ plan: CrossStoreKeyRollbackPlan,
        transactionId: UUID
    ) throws {
        try update(
            transactionId: transactionId,
            operation: "plan_key",
            requiresApplying: true
        ) { record in
            guard !record.insertedKeys.contains(where: { $0.id == plan.id }) else { return }
            record.insertedKeys.append(plan)
        }
    }

    nonisolated func planInsertedAssignment(
        _ plan: CrossStoreAssignmentRollbackPlan,
        transactionId: UUID
    ) throws {
        try update(
            transactionId: transactionId,
            operation: "plan_assignment",
            requiresApplying: true
        ) { record in
            guard !record.insertedAssignments.contains(where: {
                $0.keyId == plan.keyId
                    && $0.consumerToolId == plan.consumerToolId
            }) else { return }
            record.insertedAssignments.append(plan)
        }
    }

    nonisolated func decideCommit(transactionId: UUID) throws {
        try update(
            transactionId: transactionId,
            operation: "decide_commit",
            requiresApplying: false
        ) { record in
            guard record.phase != .completed else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_journal_decide_commit",
                    detail: "transaction_already_completed"
                )
            }
            record.phase = .commitDecided
        }
    }

    nonisolated func clear(transactionId: UUID) throws {
        try withExclusiveJournalLock {
            guard var record = try readLocked() else { return }
            guard record.transactionId == transactionId else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_journal_clear",
                    detail: "transaction_mismatch"
                )
            }
            if record.phase != .completed {
                record.phase = .completed
                try writeLocked(record)
            }
            try removeMarkerLocked(operation: "cross_store_journal_clear")
        }
    }

    nonisolated func discardForCommittedErase(
        authorization: CommittedEraseToken
    ) throws {
        try authorization.validate(operation: "cross_store_journal_committed_erase")
        try withExclusiveJournalLock {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                var tombstone = CrossStoreTransactionRecord(kind: .createKey)
                tombstone.phase = .completed
                try writeLocked(tombstone)
            }
            try removeMarkerLocked(operation: "cross_store_journal_committed_erase")
        }
    }

    private nonisolated func update(
        transactionId: UUID,
        operation: String,
        requiresApplying: Bool,
        mutate: (inout CrossStoreTransactionRecord) throws -> Void
    ) throws {
        try withExclusiveJournalLock {
            guard var record = try readLocked() else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_journal_\(operation)",
                    detail: "marker_missing"
                )
            }
            try record.validateForRecovery()
            guard record.transactionId == transactionId else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_journal_\(operation)",
                    detail: "transaction_mismatch"
                )
            }
            if requiresApplying, record.phase != .applying {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_journal_\(operation)",
                    detail: "transaction_already_commit_decided"
                )
            }
            try mutate(&record)
            try record.validateForRecovery()
            try writeLocked(record)
        }
    }

    private nonisolated func withExclusiveJournalLock<T>(
        _ body: () throws -> T
    ) throws -> T {
        processLock.lock()
        defer { processLock.unlock() }

        #if canImport(Darwin)
        let directory = lockFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw storageFailure(operation: "cross_store_journal_lock", error: error)
        }
        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw storageFailure(
                operation: "cross_store_journal_lock",
                error: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            )
        }
        defer { _ = close(descriptor) }
        var lockResult: Int32
        repeat {
            lockResult = flock(descriptor, LOCK_EX)
        } while lockResult != 0 && errno == EINTR
        guard lockResult == 0 else {
            throw storageFailure(
                operation: "cross_store_journal_lock",
                error: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            )
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        #endif

        return try body()
    }

    private nonisolated func readLocked() throws -> CrossStoreTransactionRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(
                CrossStoreTransactionRecord.self,
                from: Data(contentsOf: fileURL)
            )
        } catch let error as ApiRelayError {
            throw error
        } catch {
            throw storageFailure(operation: "cross_store_journal_read", error: error)
        }
    }

    private nonisolated func writeLocked(_ record: CrossStoreTransactionRecord) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".cross-store-transaction-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(record)
            try data.write(to: temporary, options: [])
            try syncFileLocked(temporary)
            #if canImport(Darwin)
            let renameResult = temporary.path.withCString { source in
                fileURL.path.withCString { destination in
                    rename(source, destination)
                }
            }
            guard renameResult == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            #else
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
            #endif
            try syncDirectoryLocked(directory)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw storageFailure(operation: "cross_store_journal_write", error: error)
        }
    }

    private nonisolated func removeMarkerLocked(operation: String) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
            do {
                try syncDirectoryLocked(fileURL.deletingLastPathComponent())
            } catch {
                // The logical state is already absent in this process. Every
                // caller first fsyncs a `.completed` tombstone, so a directory
                // entry that resurfaces after a crash can only request another
                // harmless unlink.
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return
                }
                throw error
            }
        } catch {
            throw storageFailure(operation: operation, error: error)
        }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: operation,
                detail: "marker_remains"
            )
        }
    }

    private nonisolated func syncFileLocked(_ url: URL) throws {
        #if canImport(Darwin)
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #endif
    }

    private nonisolated func syncDirectoryLocked(_ url: URL) throws {
        #if canImport(Darwin)
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #endif
    }

    private nonisolated static func defaultFileURL() -> URL {
        if AppRuntime.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "ApiRelay-CrossStoreTransaction-tests-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                    isDirectory: true
                )
                .appendingPathComponent("journal-v2.json", isDirectory: false)
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.apirelay.ApiRelay",
                isDirectory: true
            )
            .appendingPathComponent("Security", isDirectory: true)
            .appendingPathComponent("cross-store-transaction-v2.json", isDirectory: false)
    }

    private nonisolated func storageFailure(
        operation: String,
        error: Error
    ) -> ApiRelayError {
        .storageRecoveryFailed(
            operation: operation,
            detail: "cause=\(String(reflecting: type(of: error)))"
        )
    }
}
