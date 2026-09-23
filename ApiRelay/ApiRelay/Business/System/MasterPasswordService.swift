import Foundation
import Security
import CommonCrypto

/// 设密与校验共用的口令规则（CL-005：最短 4 位，不强制混搭）。
/// 须 `nonisolated`：`MasterPasswordService` 是 actor，不能调默认 MainActor 的类型。
enum MasterPasswordPolicy: Sendable {
    nonisolated static let minimumLength = 4

    struct Evaluation: Equatable, Sendable {
        var trimmedLength: Int
        var meetsMinimumLength: Bool
        var confirmMatches: Bool

        nonisolated var canSave: Bool { meetsMinimumLength && confirmMatches }
    }

    nonisolated static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func evaluate(password: String, confirm: String) -> Evaluation {
        let passwordTrimmed = trimmed(password)
        let confirmTrimmed = trimmed(confirm)
        return Evaluation(
            trimmedLength: passwordTrimmed.count,
            meetsMinimumLength: passwordTrimmed.count >= minimumLength,
            confirmMatches: passwordTrimmed == confirmTrimmed
        )
    }
}

protocol MasterPasswordServing: Actor {
    func isSet() async throws -> Bool
    /// 材料三态。Keychain 读取失败 MUST 为 `unreadable`，MUST NOT 当成未设。
    func materialStatus() async -> AppPasswordMaterialStatus
    /// 每次成功写入或删除材料后递增。供设密/恢复协调拒绝过期请求。
    func materialRevision() async -> UInt64
    /// 仅当材料未设时写入。已设或不可读 MUST NOT 覆盖。日常改密走 `changePassword`。
    func setPassword(_ password: String, committing: KeychainCommit) async throws
    func verify(_ password: String) async throws -> Bool
    func changePassword(current: String, new: String, committing: KeychainCommit) async throws
    /// 只删除本机 `.masterpw` 材料。MUST NOT 清 `.keys` / `.admin` / `.backuppw`。
    /// 测试清理和无版本快照的旧入口。产品恢复 MUST 走 `reset(expectedRevision:)`。
    func reset() async throws
    /// 在同一排他提交里核对预期版本再删除。版本已变或正有材料变更时 MUST NOT 删他人新材料。
    func reset(expectedRevision: UInt64, committing: KeychainCommit) async throws
    /// 材料仍为已设且版本未变时，占住排他权执行 `perform`（不递增 revision）。
    /// 供切档/创建后 persist，避免保存密码档期间被恢复删掉材料。
    func withUnchangedSetMaterial(
        expectedRevision: UInt64,
        perform: @Sendable () async throws -> Void
    ) async throws
}

extension MasterPasswordServing {
    func setPassword(_ password: String) async throws {
        try await setPassword(password, committing: { operation in try operation() })
    }

    func setPassword(
        _ password: String,
        authorizing: @Sendable () throws -> Void
    ) async throws {
        try await setPassword(password, committing: { operation in
            try authorizing()
            try operation()
        })
    }

    func changePassword(current: String, new: String) async throws {
        try await changePassword(
            current: current,
            new: new,
            committing: { operation in try operation() }
        )
    }

    func reset(expectedRevision: UInt64) async throws {
        try await reset(
            expectedRevision: expectedRevision,
            committing: { operation in try operation() }
        )
    }

    func reset(
        expectedRevision: UInt64,
        authorizing: @Sendable () throws -> Void
    ) async throws {
        try await reset(expectedRevision: expectedRevision, committing: { operation in
            try authorizing()
            try operation()
        })
    }
}

actor MasterPasswordService: MasterPasswordServing {
    /// 旧材料仍接受较低工作因子，成功验证后再无感升级；新材料采用当前基线。
    private static let minimumStoredIterations: UInt32 = 10_000
    private static let minimumNewIterations: UInt32 = 600_000
    private static let maximumStoredIterations: UInt32 = 2_000_000
    /// NIST SP 800-63B activation-secret retry ceiling. Reaching the ceiling
    /// disables this local verifier until the existing device-owner recovery
    /// flow resets/re-enrolls it.
    private static let maximumConsecutiveFailures = 10
    private static let saltByteCount = 16
    private static let hashByteCount = 32
    private let keychain: KeychainStoring
    private let mutationGate: StorageMutationGate
    private let account = KeychainStore.masterPasswordAccount
    private let now: @Sendable () -> Date
    private(set) var calibratedIterations: UInt32
    private var revision: UInt64 = 0
    private var mutationInFlight = false

    init(
        keychain: KeychainStoring,
        calibratedIterations: UInt32? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        mutationGate: StorageMutationGate = StorageMutationGate()
    ) {
        self.keychain = keychain
        self.mutationGate = mutationGate
        self.calibratedIterations = calibratedIterations ?? Self.calibrateIterations()
        self.now = now
    }

    func isSet() async throws -> Bool {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_read")
        defer { storagePermit.finish() }
        do {
            let stored = try await keychain.read(service: .masterpw, account: account)
            guard Self.decodePayload(stored) != nil else {
                throw ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "material_unreadable"
                )
            }
            return true
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            return false
        }
    }

    func materialStatus() async -> AppPasswordMaterialStatus {
        let storagePermit: StorageMutationPermit
        do {
            storagePermit = try mutationGate.beginNormal(operation: "master_password_status")
        } catch {
            return .unreadable
        }
        defer { storagePermit.finish() }
        do {
            let stored = try await keychain.read(service: .masterpw, account: account)
            return Self.decodePayload(stored) == nil ? .unreadable : .set
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            return .unset
        } catch {
            return .unreadable
        }
    }

    func materialRevision() async -> UInt64 {
        revision
    }

    func setPassword(_ password: String, committing: KeychainCommit) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_set")
        defer { storagePermit.finish() }
        try await mutateMaterial {
            try Self.rejectCreate(await materialStatus())
            try await writeMaterial(password, committing: committing)
        }
    }

    func verify(_ password: String) async throws -> Bool {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_verify")
        defer { storagePermit.finish() }
        // `KeychainStoring` is another actor. Without an explicit transaction,
        // two verification calls can both read the same retry counter while this
        // actor is suspended, then overwrite each other's increment. Serialize
        // the complete read/derive/write sequence so retry throttling is durable
        // under concurrent windows and operations as well as across relaunches.
        return try await withExclusiveAccess(bumpRevision: false) {
            try await verifyDuringExclusiveAccess(password)
        }
    }

    private func verifyDuringExclusiveAccess(_ password: String) async throws -> Bool {
        let stored = try await keychain.read(service: .masterpw, account: account)
        guard var parts = Self.decodePayload(stored) else {
            throw ApiRelayError.validationFailed(
                field: "masterPassword",
                reason: "material_unreadable"
            )
        }
        if parts.consecutiveFailures >= Self.maximumConsecutiveFailures {
            throw ApiRelayError.masterPasswordLocked
        }
        let currentTime = now().timeIntervalSince1970
        if let until = parts.retryAllowedAt, currentTime < until {
            throw ApiRelayError.masterPasswordRetryDelayed(
                secondsRemaining: Int(ceil(until - currentTime))
            )
        }
        // Creation stores the trimmed password. Verification must apply the same
        // canonicalization so every entry surface (SwiftUI fields and native
        // fallback dialogs) accepts exactly the credential that was created.
        let canonical = MasterPasswordPolicy.trimmed(password)
        let derived = try Self.derive(password: canonical, salt: parts.salt, iterations: parts.iterations)
        let ok = Self.constantTimeEqual(derived, parts.hash)
        if ok {
            // A successful legacy-v1 verification upgrades the record in place.
            // It also durably clears retry state, so relaunching cannot resurrect
            // an old delay and a successful attempt cannot leave stale failures.
            if parts.formatVersion == 1
                || parts.consecutiveFailures != 0
                || parts.retryAllowedAt != nil
                || parts.iterations < calibratedIterations
            {
                if parts.iterations < calibratedIterations {
                    parts.salt = try Self.randomSalt()
                    parts.iterations = calibratedIterations
                    parts.hash = try Self.derive(
                        password: canonical,
                        salt: parts.salt,
                        iterations: parts.iterations
                    )
                }
                parts.formatVersion = 2
                parts.consecutiveFailures = 0
                parts.retryAllowedAt = nil
                try await save(parts)
            }
        } else {
            parts.formatVersion = 2
            parts.consecutiveFailures += 1
            if parts.consecutiveFailures >= 3,
               parts.consecutiveFailures < Self.maximumConsecutiveFailures {
                let delay = min(pow(2.0, Double(parts.consecutiveFailures - 2)), 60)
                parts.retryAllowedAt = currentTime + delay
            } else {
                parts.retryAllowedAt = nil
            }
            // Retry state lives beside the verifier in the same Keychain item.
            // A force-quit/relaunch therefore cannot reset the attempt counter.
            try await save(parts)
            if parts.consecutiveFailures >= Self.maximumConsecutiveFailures {
                throw ApiRelayError.masterPasswordLocked
            }
        }
        return ok
    }

    func changePassword(current: String, new: String, committing: KeychainCommit) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_change")
        defer { storagePermit.finish() }
        try await mutateMaterial {
            // The outer mutation already owns the exclusive material transaction;
            // calling public `verify` here would attempt to acquire it twice.
            guard try await verifyDuringExclusiveAccess(current) else {
                throw ApiRelayError.authenticationFailed
            }
            try Self.rejectReplace(await materialStatus())
            try await writeMaterial(new, committing: committing)
        }
    }

    func reset() async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_reset")
        defer { storagePermit.finish() }
        try await mutateMaterial {
            try await keychain.delete(service: .masterpw, account: account)
        }
    }

    func reset(expectedRevision: UInt64, committing: KeychainCommit) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_reset")
        defer { storagePermit.finish() }
        try await mutateMaterial {
            guard revision == expectedRevision else {
                throw ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "stale_concurrent"
            )
            }
            try await keychain.delete(
                service: .masterpw,
                account: account,
                committing: committing
            )
        }
    }

    func withUnchangedSetMaterial(
        expectedRevision: UInt64,
        perform: @Sendable () async throws -> Void
    ) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "master_password_policy")
        defer { storagePermit.finish() }
        try await withExclusiveAccess(bumpRevision: false) {
            guard revision == expectedRevision else {
                throw ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "stale_concurrent"
                )
            }
            try Self.rejectReplace(await materialStatus())
            try await perform()
        }
    }

    private func mutateMaterial(_ body: () async throws -> Void) async throws {
        try await withExclusiveAccess(bumpRevision: true, body)
    }

    private func withExclusiveAccess<Result: Sendable>(
        bumpRevision: Bool,
        _ body: () async throws -> Result
    ) async throws -> Result {
        guard !mutationInFlight else {
            throw ApiRelayError.validationFailed(
                field: "masterPassword",
                reason: "stale_concurrent"
            )
        }
        mutationInFlight = true
        defer { mutationInFlight = false }
        let result = try await body()
        if bumpRevision {
            revision += 1
        }
        return result
    }

    private func writeMaterial(
        _ password: String,
        committing: KeychainCommit
    ) async throws {
        let trimmed = MasterPasswordPolicy.trimmed(password)
        guard trimmed.count >= MasterPasswordPolicy.minimumLength else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "too_short")
        }
        let salt = try Self.randomSalt()
        let derived = try Self.derive(password: trimmed, salt: salt, iterations: calibratedIterations)
        let payload = StoredPayload(
            formatVersion: 2,
            salt: salt,
            iterations: calibratedIterations,
            hash: derived,
            consecutiveFailures: 0,
            retryAllowedAt: nil
        )
        try await save(payload, committing: committing)
    }

    nonisolated private static func rejectCreate(_ status: AppPasswordMaterialStatus) throws {
        switch status {
        case .unset:
            return
        case .set:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "already_set")
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }

    nonisolated private static func rejectReplace(_ status: AppPasswordMaterialStatus) throws {
        switch status {
        case .set:
            return
        case .unset:
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "master_password_not_configured"
            )
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }

    private static func calibrateIterations() -> UInt32 {
        let salt = Data(repeating: 1, count: 16)
        var iterations = minimumNewIterations
        let targetSeconds = 0.25
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try? derive(password: "calibrate", salt: salt, iterations: iterations)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed <= 0 { break }
            let scaled = Double(iterations) * (targetSeconds / elapsed)
            iterations = UInt32(
                min(
                    max(scaled, Double(minimumNewIterations)),
                    Double(maximumStoredIterations)
                )
            )
        }
        return iterations
    }

    private static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        return Data(bytes)
    }

    private static func derive(password: String, salt: Data, iterations: UInt32) throws -> Data {
        let passwordData = Data(password.utf8)
        var derived = Data(count: hashByteCount)
        let result = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                passwordData.withUnsafeBytes { passPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress,
                        hashByteCount
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "pbkdf2_failed")
        }
        return derived
    }

    private struct StoredPayload: Sendable {
        var formatVersion: Int
        var salt: Data
        var iterations: UInt32
        var hash: Data
        var consecutiveFailures: Int
        var retryAllowedAt: TimeInterval?
    }

    private func save(_ payload: StoredPayload) async throws {
        try await keychain.save(
            Self.encodePayload(payload),
            service: .masterpw,
            account: account
        )
    }

    private func save(_ payload: StoredPayload, committing: KeychainCommit) async throws {
        try await keychain.save(
            Self.encodePayload(payload),
            service: .masterpw,
            account: account,
            committing: committing
        )
    }

    private static func encodePayload(_ payload: StoredPayload) -> String {
        let retry = payload.retryAllowedAt.map { String($0) } ?? "0"
        return "v2:\(payload.iterations):\(payload.salt.base64EncodedString()):\(payload.hash.base64EncodedString()):\(payload.consecutiveFailures):\(retry)"
    }

    private static func decodePayload(_ payload: String) -> StoredPayload? {
        let parts = payload.split(separator: ":").map(String.init)
        guard parts.count >= 4,
              let iterations = UInt32(parts[1]),
              let salt = Data(base64Encoded: parts[2]),
              let hash = Data(base64Encoded: parts[3]),
              (minimumStoredIterations...maximumStoredIterations).contains(iterations),
              salt.count == saltByteCount,
              hash.count == hashByteCount else {
            return nil
        }
        if parts.count == 4, parts[0] == "v1" {
            return StoredPayload(
                formatVersion: 1,
                salt: salt,
                iterations: iterations,
                hash: hash,
                consecutiveFailures: 0,
                retryAllowedAt: nil
            )
        }
        guard parts.count == 6,
              parts[0] == "v2",
              let failures = Int(parts[4]),
              (0...maximumConsecutiveFailures).contains(failures),
              let retryRaw = TimeInterval(parts[5]),
              retryRaw.isFinite,
              retryRaw >= 0 else {
            return nil
        }
        return StoredPayload(
            formatVersion: 2,
            salt: salt,
            iterations: iterations,
            hash: hash,
            consecutiveFailures: failures,
            retryAllowedAt: retryRaw == 0 ? nil : retryRaw
        )
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
