import Foundation
import CryptoKit
import SwiftData

protocol SecureBackupServing: Actor {
    func exportBackup(passphrase: String, purpose: BackupPurpose) async throws -> Data
    func importBackup(data: Data, passphrase: String) async throws -> ImportSummary
}

struct ImportSummary: Sendable {
    let accountCount: Int
    let keyCount: Int
    let purpose: BackupPurpose
}

actor SecureBackupService: SecureBackupServing {
    private let gate: RevealGate
    private let keychain: KeychainStore
    private let accounts: UpstreamAccountRepository
    private let keys: APIKeyRecordRepository

    init(
        gate: RevealGate,
        keychain: KeychainStore,
        modelContainer: ModelContainer
    ) {
        self.gate = gate
        self.keychain = keychain
        self.accounts = UpstreamAccountRepository(modelContainer: modelContainer)
        self.keys = APIKeyRecordRepository(modelContainer: modelContainer)
    }

    func exportBackup(passphrase: String, purpose: BackupPurpose = .fullBackup) async throws -> Data {
        try await gate.confirmMandatory(reason: String(localized: "gate.exportBackup"))
        let accountDTOs = try await accounts.fetchAll()
        let keyDTOs = try await keys.fetch(lifecycles: [.active, .revokedUpstream])
        var keyPayloads: [[String: Any]] = []
        for key in keyDTOs {
            let secret = (try? await keychain.read(service: .keys, account: key.id)) ?? ""
            keyPayloads.append([
                "id": key.id.uuidString,
                "accountId": key.accountId.uuidString,
                "displayName": key.displayName,
                "maskedHint": key.maskedHint as Any,
                "secret": secret,
                "lifecycle": key.lifecycle.rawValue,
            ])
        }
        let scopeKeyIds = keyDTOs.map(\.id.uuidString)
        let plaintext: [String: Any] = [
            "version": 1,
            "purpose": purpose.rawValue,
            "scope": ["keyIds": scopeKeyIds],
            "accounts": accountDTOs.map {
                [
                    "id": $0.id.uuidString,
                    "platform": $0.platform,
                    "displayName": $0.displayName,
                    "customBaseURL": $0.customBaseURL as Any,
                ] as [String: Any]
            },
            "keys": keyPayloads,
        ]
        let json = try JSONSerialization.data(withJSONObject: plaintext, options: [.sortedKeys])
        return try Self.encrypt(json, passphrase: passphrase)
    }

    func importBackup(data: Data, passphrase: String) async throws -> ImportSummary {
        let json = try Self.decrypt(data, passphrase: passphrase)
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let purposeRaw = root["purpose"] as? String,
              let purpose = BackupPurpose(rawValue: purposeRaw),
              let accountsArr = root["accounts"] as? [[String: Any]],
              let keysArr = root["keys"] as? [[String: Any]] else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        _ = accountsArr
        _ = keysArr
        // V1：导入实现保留格式校验；完整合并逻辑可在设置页调用后扩展。
        return ImportSummary(accountCount: accountsArr.count, keyCount: keysArr.count, purpose: purpose)
    }

    private static func encrypt(_ data: Data, passphrase: String) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw ApiRelayError.validationFailed(field: "backup", reason: "seal_failed")
        }
        var out = Data("ARBK1".utf8)
        out.append(salt)
        out.append(combined)
        return out
    }

    private static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        let magic = Data("ARBK1".utf8)
        guard data.count > magic.count + 16 + 28, data.prefix(magic.count) == magic else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let sealedData = data.subdata(in: (magic.count + 16)..<data.count)
        let key = deriveKey(passphrase: passphrase, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ApiRelayError.backupPassphraseIncorrect
        }
    }

    private static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        let input = Data(passphrase.utf8) + salt
        let hash = SHA256.hash(data: input)
        return SymmetricKey(data: hash)
    }
}
