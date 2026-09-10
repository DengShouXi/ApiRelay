import Foundation
import CryptoKit
import CommonCrypto
import SwiftData

protocol SecureBackupServing: Actor {
    func inspectProtection(_ data: Data) throws -> BackupFileProtection
    func exportBackup(passphrase: String?, purpose: BackupPurpose) async throws -> BackupExportResult
    func importBackup(data: Data, passphrase: String?) async throws -> ImportSummary
}

struct BackupExportResult: Sendable {
    let data: Data
    /// 元信息在备份里、但本机 Keychain 读不到明文的密钥数。导出仍会带上空字符串，导入后须明示。
    let keysWithoutSecretCount: Int
}

struct ImportSummary: Sendable {
    let accountCount: Int
    let keyCount: Int
    let toolCount: Int
    let skippedKeyCount: Int
    /// 已写入元信息、但备份里明文为空、本机也没有写入 Keychain 的密钥数。
    let keysWithoutSecretCount: Int
    let purpose: BackupPurpose
}

enum SecureBackupFile: Sendable {
    nonisolated static var passphraseMagic: Data { Data("ARBK1".utf8) }
    nonisolated static var unprotectedMagic: Data { Data("ARBN1".utf8) }
    nonisolated static var pathExtension: String { "apirelaybackup" }
    nonisolated static var uti: String { "com.apirelay.backup" }
    nonisolated static var kdfIterations: UInt32 { 210_000 }
}

extension Notification.Name {
    /// 加密备份导入完成后发出；主列表据此刷新。
    static let vaultDidImportBackup = Notification.Name("com.apirelay.vaultDidImportBackup")
}

actor SecureBackupService: SecureBackupServing {
    private let gate: RevealGateServing
    private let keychain: KeychainStoring
    private let accounts: UpstreamAccountRepository
    private let keys: APIKeyRecordRepository
    private let tools: ConsumerToolRepository
    private let assignments: KeyAssignmentRepository
    private let sessionLock: any SessionLockQuerying

    init(
        gate: RevealGateServing,
        keychain: KeychainStoring,
        modelContainer: ModelContainer,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock()
    ) {
        self.gate = gate
        self.keychain = keychain
        self.accounts = UpstreamAccountRepository(modelContainer: modelContainer)
        self.keys = APIKeyRecordRepository(modelContainer: modelContainer)
        self.tools = ConsumerToolRepository(modelContainer: modelContainer)
        self.assignments = KeyAssignmentRepository(modelContainer: modelContainer)
        self.sessionLock = sessionLock
    }

    func inspectProtection(_ data: Data) throws -> BackupFileProtection {
        if data.starts(with: SecureBackupFile.passphraseMagic) {
            return .passphraseProtected
        }
        if data.starts(with: SecureBackupFile.unprotectedMagic) {
            return .unprotected
        }
        throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
    }

    func exportBackup(passphrase: String? = nil, purpose: BackupPurpose = .fullBackup) async throws -> BackupExportResult {
        if sessionLock.isSessionLocked() { throw ApiRelayError.sessionLocked }
        try await gate.confirmMandatory(reason: String(localized: "gate.exportBackup"))
        let encoded = try await encodeVaultJSON(purpose: purpose)
        let data: Data
        if let passphrase {
            let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ApiRelayError.validationFailed(field: "backupPassphrase", reason: "empty")
            }
            data = try Self.encrypt(encoded.json, passphrase: trimmed)
        } else {
            var out = Data()
            out.append(SecureBackupFile.unprotectedMagic)
            out.append(encoded.json)
            data = out
        }
        return BackupExportResult(
            data: data,
            keysWithoutSecretCount: encoded.keysWithoutSecretCount
        )
    }

    func importBackup(data: Data, passphrase: String?) async throws -> ImportSummary {
        if sessionLock.isSessionLocked() { throw ApiRelayError.sessionLocked }
        try await gate.confirmMandatory(reason: String(localized: "gate.importBackup"))
        let json: Data
        switch try inspectProtection(data) {
        case .unprotected:
            json = Data(data.dropFirst(SecureBackupFile.unprotectedMagic.count))
        case .passphraseProtected:
            let trimmed = passphrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw ApiRelayError.backupPassphraseIncorrect
            }
            json = try Self.decrypt(data, passphrase: trimmed)
        }
        return try await applyVaultJSON(json)
    }

    private func encodeVaultJSON(purpose: BackupPurpose) async throws -> (json: Data, keysWithoutSecretCount: Int) {
        let accountDTOs = try await accounts.fetchAll()
        let keyDTOs = try await keys.fetch(lifecycles: [.active, .revokedUpstream])
        let toolDTOs = try await tools.fetchAll(includeHidden: true, includeDeleted: false)

        var keyPayloads: [[String: Any]] = []
        var assignmentPayloads: [[String: Any]] = []
        var keysWithoutSecretCount = 0
        for key in keyDTOs {
            let secret = (try? await keychain.read(service: .keys, account: key.id)) ?? ""
            if secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                keysWithoutSecretCount += 1
            }
            keyPayloads.append(
                Self.compact([
                    "id": key.id.uuidString,
                    "accountId": key.accountId.uuidString,
                    "displayName": key.displayName,
                    "secret": secret,
                    "lifecycle": key.lifecycle.rawValue,
                    "origin": key.origin.rawValue,
                    "notes": key.notes,
                    "sortOrder": key.sortOrder,
                    "avatarSymbol": key.avatarSymbol,
                    "avatarColor": key.avatarColor,
                ])
            )
            for toolId in key.consumerToolIds {
                assignmentPayloads.append([
                    "keyId": key.id.uuidString,
                    "consumerToolId": toolId.uuidString,
                ])
            }
        }

        let plaintext: [String: Any] = [
            "version": 1,
            "purpose": purpose.rawValue,
            "scope": ["keyIds": keyDTOs.map(\.id.uuidString)],
            "accounts": accountDTOs.map {
                Self.compact([
                    "id": $0.id.uuidString,
                    "platform": $0.platform,
                    "customPlatformName": $0.customPlatformName,
                    "displayName": $0.displayName,
                    "customBaseURL": $0.customBaseURL,
                    "notes": $0.notes,
                    "sortOrder": $0.sortOrder,
                    "avatarSymbol": $0.avatarSymbol,
                    "avatarColor": $0.avatarColor,
                ])
            },
            "keys": keyPayloads,
            "tools": toolDTOs.map {
                Self.compact([
                    "id": $0.id.uuidString,
                    "name": $0.name,
                    "iconSymbol": $0.iconSymbol,
                    "avatarSymbol": $0.avatarSymbol,
                    "avatarColor": $0.avatarColor,
                    "isPreset": $0.isPreset,
                    "isHidden": $0.isHidden,
                    "notes": $0.notes,
                    "sortOrder": $0.sortOrder,
                ])
            },
            "assignments": assignmentPayloads,
        ]
        let json = try JSONSerialization.data(withJSONObject: plaintext, options: [.sortedKeys])
        return (json, keysWithoutSecretCount)
    }

    private func applyVaultJSON(_ json: Data) async throws -> ImportSummary {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let version = root["version"] as? Int,
              version == 1,
              let purposeRaw = root["purpose"] as? String,
              let purpose = BackupPurpose(rawValue: purposeRaw),
              let accountsArr = root["accounts"] as? [[String: Any]],
              let keysArr = root["keys"] as? [[String: Any]] else {
            let found = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])
                .flatMap { $0["version"] as? Int } ?? 0
            throw ApiRelayError.backupVersionUnsupported(found: found, supported: 1)
        }
        let toolsArr = root["tools"] as? [[String: Any]] ?? []
        let assignmentsArr = root["assignments"] as? [[String: Any]] ?? []

        var importedAccounts = 0
        for account in accountsArr {
            guard let id = Self.uuid(account["id"]),
                  let platform = account["platform"] as? String,
                  let displayName = account["displayName"] as? String else { continue }
            let draft = UpstreamAccountDraft(
                platform: platform,
                customPlatformName: account["customPlatformName"] as? String,
                displayName: displayName,
                customBaseURL: account["customBaseURL"] as? String,
                notes: account["notes"] as? String,
                sortOrder: account["sortOrder"] as? Int ?? 0,
                avatarSymbol: account["avatarSymbol"] as? String,
                avatarColor: account["avatarColor"] as? String
            )
            if try await accounts.insertIfAbsent(draft, id: id) {
                importedAccounts += 1
            }
        }

        var importedTools = 0
        for tool in toolsArr {
            guard let id = Self.uuid(tool["id"]),
                  let name = tool["name"] as? String else { continue }
            let draft = ConsumerToolDraft(
                name: name,
                iconSymbol: tool["iconSymbol"] as? String,
                isPreset: false,
                notes: tool["notes"] as? String,
                sortOrder: tool["sortOrder"] as? Int ?? 0,
                avatarSymbol: tool["avatarSymbol"] as? String,
                avatarColor: tool["avatarColor"] as? String
            )
            guard try await tools.insertIfAbsent(draft, id: id) else { continue }
            if tool["isHidden"] as? Bool == true {
                try await tools.update(id: id, patch: ConsumerToolPatch(isHidden: true))
            }
            importedTools += 1
        }

        var importedKeys = 0
        var skippedKeys = 0
        var keysWithoutSecret = 0
        for key in keysArr {
            guard let id = Self.uuid(key["id"]),
                  let accountId = Self.uuid(key["accountId"]),
                  let displayName = key["displayName"] as? String else {
                skippedKeys += 1
                continue
            }
            guard try await accounts.fetch(id: accountId) != nil else {
                skippedKeys += 1
                continue
            }
            let secret = (key["secret"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let origin = (key["origin"] as? String).flatMap(KeyOrigin.init(rawValue:)) ?? .manualEntry
            let draft = KeyRecordDraft(
                accountId: accountId,
                displayName: displayName,
                origin: origin,
                notes: key["notes"] as? String,
                sortOrder: key["sortOrder"] as? Int ?? 0,
                avatarSymbol: key["avatarSymbol"] as? String,
                avatarColor: key["avatarColor"] as? String
            )
            guard try await keys.insertIfAbsent(draft, id: id) else {
                skippedKeys += 1
                continue
            }
            if let lifecycleRaw = key["lifecycle"] as? String,
               let lifecycle = KeyLifecycle.init(rawValue: lifecycleRaw),
               lifecycle != .active {
                try await keys.update(id: id, patch: KeyRecordPatch(lifecycle: lifecycle))
            }
            if secret.isEmpty {
                keysWithoutSecret += 1
            } else {
                try await keychain.save(secret, service: .keys, account: id)
            }
            importedKeys += 1
        }

        for row in assignmentsArr {
            guard let keyId = Self.uuid(row["keyId"]),
                  let toolId = Self.uuid(row["consumerToolId"]) else { continue }
            guard try await keys.fetch(id: keyId) != nil else { continue }
            guard try await tools.fetch(id: toolId) != nil else { continue }
            try await assignments.add(keyId: keyId, consumerToolId: toolId)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .vaultDidImportBackup, object: nil)
        }
        return ImportSummary(
            accountCount: importedAccounts,
            keyCount: importedKeys,
            toolCount: importedTools,
            skippedKeyCount: skippedKeys,
            keysWithoutSecretCount: keysWithoutSecret,
            purpose: purpose
        )
    }

    private static func compact(_ pairs: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in pairs {
            if let value {
                out[key] = value
            }
        }
        return out
    }

    private static func uuid(_ value: Any?) -> UUID? {
        guard let raw = value as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func encrypt(_ data: Data, passphrase: String) throws -> Data {
        let salt = randomSalt()
        let iterations = SecureBackupFile.kdfIterations
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw ApiRelayError.validationFailed(field: "backup", reason: "seal_failed")
        }
        var out = Data()
        out.append(SecureBackupFile.passphraseMagic)
        out.append(salt)
        var iterationsBE = iterations.bigEndian
        withUnsafeBytes(of: &iterationsBE) { out.append(contentsOf: $0) }
        out.append(combined)
        return out
    }

    private static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        let magic = SecureBackupFile.passphraseMagic
        let headerCount = magic.count + 16 + 4
        guard data.count > headerCount + 28, data.prefix(magic.count) == magic else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let iterationsRange = (magic.count + 16)..<(magic.count + 20)
        var iterationsBE: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &iterationsBE) { buffer in
            data.copyBytes(to: buffer, from: iterationsRange)
        }
        let iterations = UInt32(bigEndian: iterationsBE)
        guard iterations >= 10_000, iterations <= 2_000_000 else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        let sealedData = data.subdata(in: headerCount..<data.count)
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ApiRelayError.backupPassphraseIncorrect
        }
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordData = Data(passphrase.utf8)
        var derived = Data(count: 32)
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
                        32
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            throw ApiRelayError.validationFailed(field: "backup", reason: "pbkdf2_failed")
        }
        return SymmetricKey(data: derived)
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        }
        return Data(bytes)
    }
}
