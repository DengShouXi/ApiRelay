import Foundation
#if canImport(Darwin)
import Darwin
#endif

nonisolated struct VaultIntegrityIncident: Sendable, Equatable {
    let operation: String
    let detail: String
}

/// 设备本地完整性隔离标记。不得把密钥明文或用户输入写进这里。
///
/// `UserDefaults` 仅作旧版迁移与故障降级镜像。生产共享实例还使用原子替换并
/// `fsync` 的文件记录，避免已返回成功的隔离/清除只停留在进程缓存中。
nonisolated final class VaultIntegrityQuarantineStore: @unchecked Sendable {
    typealias DirectorySync = @Sendable (URL) throws -> Void

    private struct Record: Codable {
        let version: Int
        let operation: String
        let detail: String
        let recordedAt: TimeInterval
    }

    private enum DurableState {
        case absent
        case valid(Record)
        case unreadable
    }

    static let shared = VaultIntegrityQuarantineStore(
        defaults: AppRuntime.userDefaultsForCurrentRuntime(),
        fileURL: VaultIntegrityQuarantineStore.defaultFileURL()
    )

    private static let defaultKey = "com.apirelay.vault.integrity-quarantine.v1"
    private static let unreadableIncident = VaultIntegrityIncident(
        operation: "integrity_quarantine_recovery",
        detail: "durable_record_unreadable"
    )

    private let defaults: UserDefaults
    private let key: String
    private let fileURL: URL?
    private let directorySync: DirectorySync
    /// Production binds quarantine release to the exact composition-root gate.
    /// Legacy/test-only stores may leave this nil and rely on token self-check.
    private let committedEraseGate: StorageMutationGate?
    private let lock = NSLock()

    /// `fileURL == nil` intentionally preserves isolated legacy-only stores used by
    /// existing tests. Production composition uses `production(committedEraseGate:)`,
    /// which supplies both the crash-durable file and exact gate binding.
    /// Durability-specific tests inject their own file URL.
    init(
        defaults: UserDefaults,
        key: String = VaultIntegrityQuarantineStore.defaultKey,
        fileURL: URL? = nil,
        directorySync: DirectorySync? = nil,
        committedEraseGate: StorageMutationGate? = nil
    ) {
        self.defaults = defaults
        self.key = key
        self.fileURL = fileURL
        self.directorySync = directorySync ?? Self.syncDirectory
        self.committedEraseGate = committedEraseGate
    }

    /// Production composition must use this factory instead of the unbound
    /// legacy singleton so a token minted by an unrelated sealed gate cannot
    /// clear the durable fail-closed marker.
    static func production(
        committedEraseGate: StorageMutationGate
    ) -> VaultIntegrityQuarantineStore {
        VaultIntegrityQuarantineStore(
            defaults: AppRuntime.userDefaultsForCurrentRuntime(),
            fileURL: defaultFileURL(),
            committedEraseGate: committedEraseGate
        )
    }

    func currentIncident() -> VaultIntegrityIncident? {
        lock.lock()
        defer { lock.unlock() }
        return currentIncidentLocked(migrateLegacy: true)
    }

    /// Records quarantine without making an already-failing compensation path
    /// throw a second error. The legacy mirror is installed first, so a durable
    /// file failure still leaves this process and the next defaults-backed launch
    /// fail-closed.
    func quarantine(operation: String, detail: String) {
        lock.lock()
        defer { lock.unlock() }

        let recordedAt = Date().timeIntervalSince1970
        defaults.set(legacyPayload(
            operation: operation,
            detail: detail,
            recordedAt: recordedAt
        ), forKey: key)
        _ = defaults.synchronize()

        guard fileURL != nil else { return }
        try? writeRecordLocked(Record(
            version: 1,
            operation: operation,
            detail: detail,
            recordedAt: recordedAt
        ))
    }

    /// Removes quarantine only after both the legacy mirror and durable marker
    /// are verifiably absent. Any failure restores the previous marker before the
    /// error escapes, so callers must not commit/clear their outer erase journal.
    func clearAfterCommittedFullEraseDurably(
        authorization: CommittedEraseToken
    ) throws {
        if let committedEraseGate {
            try committedEraseGate.validateCommittedEraseToken(
                authorization,
                operation: "integrity_quarantine_committed_erase"
            )
        } else {
            try authorization.validate(operation: "integrity_quarantine_committed_erase")
        }
        try clearDurably()
    }

    private func clearDurably() throws {
        lock.lock()
        defer { lock.unlock() }

        let legacySnapshot = defaults.object(forKey: key)
        let durableSnapshot: Data?
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                durableSnapshot = try Data(contentsOf: fileURL)
            } catch {
                throw storageFailure(
                    operation: "integrity_quarantine_clear",
                    error: error
                )
            }
        } else {
            durableSnapshot = nil
        }

        guard legacySnapshot != nil || durableSnapshot != nil else { return }

        do {
            // Clear the non-durable mirror first. A crash before the file removal
            // leaves the durable marker and therefore remains fail-closed.
            defaults.removeObject(forKey: key)
            guard defaults.synchronize(), defaults.object(forKey: key) == nil else {
                throw QuarantinePersistenceError.defaultsClearNotVerified
            }

            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                try directorySync(fileURL.deletingLastPathComponent())
            }

            guard defaults.object(forKey: key) == nil,
                  fileURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true else {
                throw QuarantinePersistenceError.markerRemains
            }
        } catch {
            restoreLocked(
                legacySnapshot: legacySnapshot,
                durableSnapshot: durableSnapshot
            )
            throw storageFailure(
                operation: "integrity_quarantine_clear",
                error: error
            )
        }
    }

    #if DEBUG
    /// 仅供先完成显式修复的测试/维护代码清除；正常业务不得自动解封。
    func clearAfterExplicitRepairForTesting() {
        try? clearDurably()
    }
    #endif

    private func currentIncidentLocked(migrateLegacy: Bool) -> VaultIntegrityIncident? {
        switch durableStateLocked() {
        case .valid(let record):
            return VaultIntegrityIncident(
                operation: record.operation,
                detail: record.detail
            )
        case .unreadable:
            return Self.unreadableIncident
        case .absent:
            break
        }

        guard let legacyObject = defaults.object(forKey: key) else { return nil }
        guard let payload = legacyObject as? [String: Any],
              let operation = payload["operation"] as? String,
              !operation.isEmpty,
              let detail = payload["detail"] as? String,
              !detail.isEmpty else {
            return Self.unreadableIncident
        }

        if migrateLegacy, fileURL != nil {
            let recordedAt = (payload["recordedAt"] as? TimeInterval)
                ?? Date().timeIntervalSince1970
            try? writeRecordLocked(Record(
                version: 1,
                operation: operation,
                detail: detail,
                recordedAt: recordedAt
            ))
        }
        return VaultIntegrityIncident(operation: operation, detail: detail)
    }

    private func durableStateLocked() -> DurableState {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return .absent
        }
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1,
              !record.operation.isEmpty,
              !record.detail.isEmpty else {
            return .unreadable
        }
        return .valid(record)
    }

    private func restoreLocked(legacySnapshot: Any?, durableSnapshot: Data?) {
        // Restore a defaults-backed fallback before touching the file so even a
        // second crash during rollback cannot silently reopen normal access.
        if let legacySnapshot {
            defaults.set(legacySnapshot, forKey: key)
        } else if let durableSnapshot {
            defaults.set(legacyPayload(from: durableSnapshot), forKey: key)
        }
        _ = defaults.synchronize()

        guard let durableSnapshot, fileURL != nil else { return }
        try? writeDataLocked(durableSnapshot)
    }

    private func legacyPayload(from durableData: Data) -> [String: Any] {
        guard let record = try? JSONDecoder().decode(Record.self, from: durableData),
              record.version == 1,
              !record.operation.isEmpty,
              !record.detail.isEmpty else {
            return legacyPayload(
                operation: Self.unreadableIncident.operation,
                detail: Self.unreadableIncident.detail,
                recordedAt: Date().timeIntervalSince1970
            )
        }
        return legacyPayload(
            operation: record.operation,
            detail: record.detail,
            recordedAt: record.recordedAt
        )
    }

    private func legacyPayload(
        operation: String,
        detail: String,
        recordedAt: TimeInterval
    ) -> [String: Any] {
        [
            "operation": operation,
            "detail": detail,
            "recordedAt": recordedAt,
        ]
    }

    private func writeRecordLocked(_ record: Record) throws {
        do {
            try writeDataLocked(JSONEncoder().encode(record))
        } catch {
            throw storageFailure(
                operation: "integrity_quarantine_record",
                error: error
            )
        }
    }

    private func writeDataLocked(_ data: Data) throws {
        guard let fileURL else { return }
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".vault-integrity-quarantine-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: temporary, options: [])
            try Self.syncFile(temporary)
            let renameResult = temporary.path.withCString { source in
                fileURL.path.withCString { destination in
                    rename(source, destination)
                }
            }
            guard renameResult == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try directorySync(directory)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func syncFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func defaultFileURL() -> URL {
        if AppRuntime.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "ApiRelay-VaultIntegrityQuarantine-tests-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
                .appendingPathComponent("quarantine-v1.json", isDirectory: false)
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
            .appendingPathComponent("vault-integrity-quarantine-v1.json", isDirectory: false)
    }

    private func storageFailure(operation: String, error: Error) -> ApiRelayError {
        .storageRecoveryFailed(
            operation: operation,
            detail: "cause=\(String(reflecting: type(of: error)))"
        )
    }
}

private nonisolated enum QuarantinePersistenceError: Error {
    case defaultsClearNotVerified
    case markerRemains
}
