import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Persisted progress for the irreversible "erase all data" transaction.
///
/// A non-nil stage means an earlier, authenticated erase started but did not
/// reach its successful end. Startup does not resume deletion automatically:
/// the user must explicitly request erase again and authenticate again. Every
/// stage is idempotent, so that retry safely continues by replaying all stages.
nonisolated enum DataEraseStage: String, Sendable {
    case authorized
    case keychain
    case vault
    case consumerTools
    case backupContexts
    case preferences
    case entitlements
    case localSnapshots
    case clipboard
    case cloudConvergence
    case keychainConvergence
    case crossStoreJournal
    case notifying
}

protocol DataEraseJournalStoring: Sendable {
    nonisolated func mark(_ stage: DataEraseStage) throws
    nonisolated func clear() throws
    /// True even if the stored stage is from a newer/corrupt format. Callers
    /// must fail closed into device-owner recovery authentication in that case.
    nonisolated func hasPendingErase() -> Bool
    nonisolated func currentStage() -> DataEraseStage?
}

/// Crash-durable journal for the irreversible erase transaction.
///
/// UserDefaults readback only proves that the in-process cache changed; it
/// cannot prove the marker reached disk before the first Keychain deletion.
/// The file record is therefore fsynced and atomically renamed before `mark`
/// returns. Legacy defaults remain a migration/fail-closed fallback.
nonisolated final class DurableDataEraseJournal: DataEraseJournalStoring, @unchecked Sendable {
    private struct Record: Codable {
        let version: Int
        let stage: String
        let startedAt: TimeInterval
    }

    private static let stageKey = "com.apirelay.dataErase.stage.v1"
    private static let startedAtKey = "com.apirelay.dataErase.startedAt.v1"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let fileURL: URL

    nonisolated init(
        defaults: UserDefaults = AppRuntime.userDefaultsForCurrentRuntime(),
        fileURL: URL = DurableDataEraseJournal.defaultFileURL()
    ) {
        self.defaults = defaults
        self.fileURL = fileURL
    }

    nonisolated func mark(_ stage: DataEraseStage) throws {
        lock.lock()
        defer { lock.unlock() }
        let startedAt = readRecordLocked()?.startedAt
            ?? (defaults.object(forKey: Self.startedAtKey) as? TimeInterval)
            ?? Date().timeIntervalSince1970
        try writeRecordLocked(Record(
            version: 1,
            stage: stage.rawValue,
            startedAt: startedAt
        ))
        // Mirror only after the durable source is committed. A crash anywhere
        // after this point still leaves `hasPendingErase == true` via the file.
        defaults.set(stage.rawValue, forKey: Self.stageKey)
        if defaults.object(forKey: Self.startedAtKey) == nil {
            defaults.set(startedAt, forKey: Self.startedAtKey)
        }
        guard readRecordLocked()?.stage == stage.rawValue else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_journal_mark",
                detail: "stage=\(stage.rawValue)"
            )
        }
    }

    nonisolated func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        // Clearing the legacy mirror first is fail-safe: if the process dies
        // before the durable file is removed, the next launch still requires
        // authenticated recovery and replays the idempotent transaction.
        defaults.removeObject(forKey: Self.stageKey)
        defaults.removeObject(forKey: Self.startedAtKey)
        _ = defaults.synchronize()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                try syncDirectoryLocked(fileURL.deletingLastPathComponent())
            } catch {
                throw storageFailure(operation: "erase_journal_clear", error: error)
            }
        }
        guard !FileManager.default.fileExists(atPath: fileURL.path),
              defaults.object(forKey: Self.stageKey) == nil,
              defaults.object(forKey: Self.startedAtKey) == nil else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_journal_clear",
                detail: "marker_remains"
            )
        }
    }

    nonisolated func hasPendingErase() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return FileManager.default.fileExists(atPath: fileURL.path)
            || defaults.object(forKey: Self.stageKey) != nil
    }

    nonisolated func currentStage() -> DataEraseStage? {
        lock.lock()
        defer { lock.unlock() }
        if let raw = readRecordLocked()?.stage {
            return DataEraseStage(rawValue: raw)
        }
        guard let raw = defaults.string(forKey: Self.stageKey) else { return nil }
        return DataEraseStage(rawValue: raw)
    }

    private nonisolated static func defaultFileURL() -> URL {
        if AppRuntime.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "ApiRelay-DataEraseJournal-tests-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
                .appendingPathComponent("journal-v1.json", isDirectory: false)
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
            .appendingPathComponent("data-erase-journal-v1.json", isDirectory: false)
    }

    private nonisolated func readRecordLocked() -> Record? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private nonisolated func writeRecordLocked(_ record: Record) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".data-erase-journal-\(UUID().uuidString).tmp",
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
            let renameResult = temporary.path.withCString { source in
                fileURL.path.withCString { destination in
                    rename(source, destination)
                }
            }
            guard renameResult == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try syncDirectoryLocked(directory)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw storageFailure(operation: "erase_journal_mark", error: error)
        }
    }

    private nonisolated func syncFileLocked(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private nonisolated func syncDirectoryLocked(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
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
