#if DEBUG
import Foundation

/// 假主密码：内存口令。不碰 Keychain / 哈希。
actor FakeMasterPassword: MasterPasswordServing {
    var journal = FakeJournal()
    private var password: String?

    func isSet() async throws -> Bool {
        try journal.record("isSet")
        return password != nil
    }

    func setPassword(_ password: String) async throws {
        try journal.record("setPassword")
        let trimmed = MasterPasswordPolicy.trimmed(password)
        guard trimmed.count >= MasterPasswordPolicy.minimumLength else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "too_short")
        }
        self.password = trimmed
    }

    func verify(_ password: String) async throws -> Bool {
        try journal.record("verify")
        guard let stored = self.password else { return false }
        return stored == password
    }

    func changePassword(current: String, new: String) async throws {
        try journal.record("changePassword")
        guard let stored = password, stored == current else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "incorrect")
        }
        let trimmed = MasterPasswordPolicy.trimmed(new)
        guard trimmed.count >= MasterPasswordPolicy.minimumLength else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "too_short")
        }
        password = trimmed
    }

    func reset() async throws {
        try journal.record("reset")
        password = nil
    }
}
#endif
