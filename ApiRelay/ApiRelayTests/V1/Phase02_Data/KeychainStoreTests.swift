@preconcurrency import XCTest
@testable import ApiRelay
import Security

@MainActor
final class KeychainStoreTests: XCTestCase {

    private var sut: KeychainStore!

    override func setUp() async throws {
        try await super.setUp()
        sut = KeychainStore(accessGroup: nil)
    }

    override func tearDown() async throws {
        if let sut {
            for service: KeychainService in [.keys, .admin, .masterpw] {
                let listed = (try? await sut.listAccounts(service: service)) ?? []
                for account in listed {
                    try? await sut.delete(service: service, account: account)
                }
            }
        }
        sut = nil
        try await super.tearDown()
    }

    /// synchronizable 条目在部分测试宿主上返回 errSecMissingEntitlement（-34018）；真机/正式签名环境再验。
    private func skipIfMissingEntitlement(_ error: Error) throws {
        if case let ApiRelayError.keychainFailure(status) = error, status == errSecMissingEntitlement {
            throw XCTSkip("Keychain synchronizable requires full app entitlements / iCloud Keychain (status -34018)")
        }
        throw error
    }

    func testSaveReadRoundTrip_keys() async throws {
        let account = UUID()
        do {
            try await sut.save("sk-test-secret", service: .keys, account: account)
        } catch {
            try skipIfMissingEntitlement(error)
        }
        let read = try await sut.read(service: .keys, account: account)
        XCTAssertEqual(read, "sk-test-secret")
        try await sut.delete(service: .keys, account: account)
    }

    func testUpsertOverwrites() async throws {
        let account = UUID()
        do {
            try await sut.save("first", service: .keys, account: account)
            try await sut.save("second", service: .keys, account: account)
        } catch {
            try skipIfMissingEntitlement(error)
        }
        let value = try await sut.read(service: .keys, account: account)
        XCTAssertEqual(value, "second")
        try await sut.delete(service: .keys, account: account)
    }

    func testDeleteThenReadFails() async throws {
        let account = UUID()
        do {
            try await sut.save("temp", service: .keys, account: account)
        } catch {
            try skipIfMissingEntitlement(error)
        }
        try await sut.delete(service: .keys, account: account)
        do {
            _ = try await sut.read(service: .keys, account: account)
            XCTFail("expected keychainFailure")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecItemNotFound)
        }
    }

    func testListAccounts() async throws {
        let a = UUID()
        let b = UUID()
        do {
            try await sut.save("a", service: .keys, account: a)
            try await sut.save("b", service: .keys, account: b)
        } catch {
            try skipIfMissingEntitlement(error)
        }
        let listed = try await sut.listAccounts(service: .keys)
        XCTAssertTrue(listed.contains(a))
        XCTAssertTrue(listed.contains(b))
        try await sut.delete(service: .keys, account: a)
        try await sut.delete(service: .keys, account: b)
    }

    func testServiceIsolation() async throws {
        let account = UUID()
        do {
            try await sut.save("key-secret", service: .keys, account: account)
        } catch {
            try skipIfMissingEntitlement(error)
        }
        let adminListed = try await sut.listAccounts(service: .admin)
        XCTAssertFalse(adminListed.contains(account))
        try await sut.delete(service: .keys, account: account)
    }

    func testMasterPasswordServiceRoundTrip() async throws {
        let account = KeychainStore.masterPasswordAccount
        try await sut.save("verifier-material", service: .masterpw, account: account)
        let value = try await sut.read(service: .masterpw, account: account)
        XCTAssertEqual(value, "verifier-material")
        try await sut.delete(service: .masterpw, account: account)
    }

    func testAdminServiceRoundTrip() async throws {
        let account = UUID()
        do {
            try await sut.save("admin-token", service: .admin, account: account)
        } catch {
            try skipIfMissingEntitlement(error)
        }
        let value = try await sut.read(service: .admin, account: account)
        XCTAssertEqual(value, "admin-token")
        try await sut.delete(service: .admin, account: account)
    }

    /// 固化 research §1：ACL + synchronizable 互斥 → errSecParam。
    func testAccessControlPlusSynchronizableFails() throws {
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlocked,
            .biometryCurrentSet,
            nil
        ) else {
            XCTFail("could not create SecAccessControl")
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.apirelay.keychain.test.acl",
            kSecAttrAccount as String: UUID().uuidString,
            kSecValueData as String: Data("x".utf8),
            kSecAttrAccessControl as String: accessControl,
            kSecAttrSynchronizable as String: true,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        XCTAssertEqual(status, errSecParam, "ACL + synchronizable must fail with errSecParam")
    }
}
