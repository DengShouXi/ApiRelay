import Foundation
import Security
import CommonCrypto

protocol MasterPasswordServing: Actor {
    func isSet() async throws -> Bool
    func setPassword(_ password: String) async throws
    func verify(_ password: String) async throws -> Bool
    func changePassword(current: String, new: String) async throws
    /// 重置前由调用方完成 confirmMandatory。
    func reset() async throws
}

actor MasterPasswordService: MasterPasswordServing {
    private let keychain: KeychainStore
    private let account = KeychainStore.masterPasswordAccount
    private(set) var calibratedIterations: UInt32

    init(keychain: KeychainStore, calibratedIterations: UInt32? = nil) {
        self.keychain = keychain
        self.calibratedIterations = calibratedIterations ?? Self.calibrateIterations()
    }

    func isSet() async throws -> Bool {
        do {
            _ = try await keychain.read(service: .masterpw, account: account)
            return true
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            return false
        }
    }

    func setPassword(_ password: String) async throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "too_short")
        }
        let salt = Self.randomSalt()
        let derived = try Self.derive(password: trimmed, salt: salt, iterations: calibratedIterations)
        let payload = Self.encodePayload(salt: salt, iterations: calibratedIterations, hash: derived)
        try await keychain.save(payload, service: .masterpw, account: account)
    }

    func verify(_ password: String) async throws -> Bool {
        let stored = try await keychain.read(service: .masterpw, account: account)
        guard let parts = Self.decodePayload(stored) else { return false }
        let derived = try Self.derive(password: password, salt: parts.salt, iterations: parts.iterations)
        return Self.constantTimeEqual(derived, parts.hash)
    }

    func changePassword(current: String, new: String) async throws {
        guard try await verify(current) else {
            throw ApiRelayError.authenticationFailed
        }
        try await setPassword(new)
    }

    func reset() async throws {
        try await keychain.delete(service: .masterpw, account: account)
    }

    private static func calibrateIterations() -> UInt32 {
        let salt = Data(repeating: 1, count: 16)
        var iterations: UInt32 = 50_000
        let targetSeconds = 0.1
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try? derive(password: "calibrate", salt: salt, iterations: iterations)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed <= 0 { break }
            let scaled = Double(iterations) * (targetSeconds / elapsed)
            iterations = UInt32(min(max(scaled, 10_000), 500_000))
        }
        return iterations
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes)
    }

    private static func derive(password: String, salt: Data, iterations: UInt32) throws -> Data {
        let passwordData = Data(password.utf8)
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
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "pbkdf2_failed")
        }
        return derived
    }

    private static func encodePayload(salt: Data, iterations: UInt32, hash: Data) -> String {
        "v1:\(iterations):\(salt.base64EncodedString()):\(hash.base64EncodedString())"
    }

    private static func decodePayload(_ payload: String) -> (salt: Data, iterations: UInt32, hash: Data)? {
        let parts = payload.split(separator: ":").map(String.init)
        guard parts.count == 4, parts[0] == "v1",
              let iterations = UInt32(parts[1]),
              let salt = Data(base64Encoded: parts[2]),
              let hash = Data(base64Encoded: parts[3]) else {
            return nil
        }
        return (salt, iterations, hash)
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
