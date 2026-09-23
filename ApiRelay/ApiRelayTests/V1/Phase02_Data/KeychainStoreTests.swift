@preconcurrency import XCTest
@testable import ApiRelay
import Security

@MainActor
final class KeychainStoreTests: XCTestCase {

    private var sut: KeychainStore!
    #if os(macOS) && !targetEnvironment(macCatalyst)
    private var isolatedNativeMigrationPrefixes: [(prefix: String, accessGroup: String?)] = []
    #endif

    override func setUp() async throws {
        try await super.setUp()
        sut = KeychainStore.makeForTests(disableSynchronizable: false)
    }

    override func tearDown() async throws {
        if let sut {
            for service: KeychainService in [.keys, .admin, .masterpw, .backuppw] {
                let listed = (try? await sut.listAccounts(service: service)) ?? []
                for account in listed {
                    try? await sut.delete(service: service, account: account)
                }
            }
        }
        #if os(macOS) && !targetEnvironment(macCatalyst)
        for entry in isolatedNativeMigrationPrefixes {
            for service: KeychainService in [.keys, .admin, .masterpw, .backuppw] {
                deleteRawNativeItems(
                    servicePrefix: entry.prefix,
                    service: service,
                    dataProtection: true,
                    accessGroup: entry.accessGroup
                )
                deleteRawNativeItems(
                    servicePrefix: entry.prefix,
                    service: service,
                    dataProtection: false,
                    accessGroup: entry.accessGroup
                )
                if entry.accessGroup != nil {
                    deleteRawNativeItems(
                        servicePrefix: entry.prefix,
                        service: service,
                        dataProtection: false,
                        accessGroup: nil
                    )
                }
            }
        }
        isolatedNativeMigrationPrefixes = []
        #endif
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

    /// 测试写入的条目 MUST NOT 出现在生产 Service 名下。
    ///
    /// 回归的是一次真实事故：测试与宿主 App 共用同一 Keychain 访问组时，
    /// setUp 里的 `reset()` 与 tearDown 里的枚举删除会清掉用户本机的主密码与密钥明文，
    /// 表现为 App 锁屏输入正确主密码仍提示「不正确」。
    /// 此处只对生产前缀做只读枚举，不写、不删任何真实条目。
    func testTestEntriesAreInvisibleUnderProductionServiceName() async throws {
        XCTAssertNotEqual(KeychainStore.testServicePrefix, KeychainStore.productionServicePrefix)

        let account = UUID()
        do {
            try await sut.save("isolation-probe", service: .keys, account: account)
        } catch {
            try skipIfMissingEntitlement(error)
        }

        let production = KeychainStore(accessGroup: nil, allowProductionNamespaceInTests: true) // 自检豁免: 本用例专门验证测试条目在生产 Service 名下不可见，只读枚举、不写不删
        let productionAccounts = try await production.listAccounts(service: .keys)
        try await sut.delete(service: .keys, account: account)

        XCTAssertFalse(
            productionAccounts.contains(account),
            "测试条目落进了生产 Service 名，隔离失效——测试会删掉用户真实的主密码与密钥明文"
        )
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

    func testTransactionTaggedInsertCanOnlyBeDeletedByItsExactTag() async throws {
        let account = UUID()
        let owner = UUID()
        var inserted = false
        do {
            inserted = try await sut.insertIfAbsent(
                "tagged-secret",
                service: .keys,
                account: account,
                transactionTag: owner
            )
        } catch {
            try skipIfMissingEntitlement(error)
        }
        XCTAssertTrue(inserted)

        let wrongTagDeleted = try await sut.deleteIfTransactionTagMatches(
            service: .keys,
            account: account,
            transactionTag: UUID()
        )
        let stored = try await sut.read(service: .keys, account: account)
        let owningTagDeleted = try await sut.deleteIfTransactionTagMatches(
            service: .keys,
            account: account,
            transactionTag: owner
        )
        XCTAssertFalse(wrongTagDeleted)
        XCTAssertEqual(stored, "tagged-secret")
        XCTAssertTrue(owningTagDeleted)
        do {
            _ = try await sut.read(service: .keys, account: account)
            XCTFail("the owning transaction tag must delete its provisional secret")
        } catch ApiRelayError.keychainFailure(let status) {
            XCTAssertEqual(status, errSecItemNotFound)
        }
    }

    func testFinalizingTransactionTagKeepsSecretAndRevokesRollbackOwnership() async throws {
        let account = UUID()
        let owner = UUID()
        var inserted = false
        do {
            inserted = try await sut.insertIfAbsent(
                "committed-secret",
                service: .keys,
                account: account,
                transactionTag: owner
            )
        } catch {
            try skipIfMissingEntitlement(error)
        }
        XCTAssertTrue(inserted)

        try await sut.finalizeTransactionTagIfMatches(
            service: .keys,
            account: account,
            transactionTag: owner
        )
        let rollbackDeleted = try await sut.deleteIfTransactionTagMatches(
            service: .keys,
            account: account,
            transactionTag: owner
        )
        let stored = try await sut.read(service: .keys, account: account)
        XCTAssertFalse(rollbackDeleted)
        XCTAssertEqual(stored, "committed-secret")
        try await sut.delete(service: .keys, account: account)
    }

    func testDuplicateTaggedInsertCannotStealExistingOwnershipTag() async throws {
        let account = UUID()
        let firstOwner = UUID()
        let secondOwner = UUID()
        var firstInserted = false
        var secondInserted = false
        do {
            firstInserted = try await sut.insertIfAbsent(
                "first-secret",
                service: .keys,
                account: account,
                transactionTag: firstOwner
            )
            secondInserted = try await sut.insertIfAbsent(
                "replacement-secret",
                service: .keys,
                account: account,
                transactionTag: secondOwner
            )
        } catch {
            try skipIfMissingEntitlement(error)
        }
        XCTAssertTrue(firstInserted)
        XCTAssertFalse(secondInserted)

        let secondOwnerDeleted = try await sut.deleteIfTransactionTagMatches(
            service: .keys,
            account: account,
            transactionTag: secondOwner
        )
        let stored = try await sut.read(service: .keys, account: account)
        let firstOwnerDeleted = try await sut.deleteIfTransactionTagMatches(
            service: .keys,
            account: account,
            transactionTag: firstOwner
        )
        XCTAssertFalse(secondOwnerDeleted)
        XCTAssertEqual(stored, "first-secret")
        XCTAssertTrue(firstOwnerDeleted)
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

    #if os(macOS) && !targetEnvironment(macCatalyst)
    func testNativeMacReadMigratesLegacyMasterPasswordToDataProtectionKeychain() async throws {
        let (store, prefix) = makeIsolatedNativeMigrationStore()
        let account = UUID()
        try addRawNativeItem(
            "legacy-verifier",
            servicePrefix: prefix,
            service: .masterpw,
            account: account,
            dataProtection: false
        )

        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: true
            ).status,
            errSecItemNotFound
        )

        let migratedValue = try await store.read(service: .masterpw, account: account)
        XCTAssertEqual(migratedValue, "legacy-verifier")
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: true
            ).data,
            Data("legacy-verifier".utf8)
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: false
            ).status,
            errSecItemNotFound,
            "legacy 条目必须在 DP 写入并读回一致后才删除"
        )
    }

    func testNativeMacSaveUsesDataProtectionKeychainAndRemovesLegacyCopy() async throws {
        let (store, prefix) = makeIsolatedNativeMigrationStore()
        let account = UUID()
        try addRawNativeItem(
            "old-backup-passphrase",
            servicePrefix: prefix,
            service: .backuppw,
            account: account,
            dataProtection: false
        )

        try await store.save("new-backup-passphrase", service: .backuppw, account: account)

        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .backuppw,
                account: account,
                dataProtection: true
            ).data,
            Data("new-backup-passphrase".utf8)
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .backuppw,
                account: account,
                dataProtection: false
            ).status,
            errSecItemNotFound
        )
    }

    func testNativeMacDeleteRemovesDataProtectionAndLegacyCopies() async throws {
        let (store, prefix) = makeIsolatedNativeMigrationStore()
        let account = UUID()
        try await store.save("dp-value", service: .masterpw, account: account)
        try addRawNativeItem(
            "legacy-value",
            servicePrefix: prefix,
            service: .masterpw,
            account: account,
            dataProtection: false
        )

        try await store.delete(service: .masterpw, account: account)

        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: true
            ).status,
            errSecItemNotFound
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: false
            ).status,
            errSecItemNotFound
        )
    }

    func testNativeMacConflictingLegacyValueNeverOverwritesExistingDataProtectionValue() async throws {
        let (store, prefix) = makeIsolatedNativeMigrationStore()
        let account = UUID()
        try await store.save("new-dp-value", service: .masterpw, account: account)
        try addRawNativeItem(
            "stale-legacy-value",
            servicePrefix: prefix,
            service: .masterpw,
            account: account,
            dataProtection: false
        )

        let value = try await store.read(service: .masterpw, account: account)
        _ = try await store.listAccounts(service: .masterpw)

        XCTAssertEqual(value, "new-dp-value")
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: true
            ).data,
            Data("new-dp-value".utf8),
            "迁移不得用 stale legacy 值覆盖已经存在的 DP 值"
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: false
            ).data,
            Data("stale-legacy-value".utf8),
            "冲突值不能在未证明等价时被静默删除；显式 delete/erase 会同时清理"
        )
    }

    func testNativeMacListMergesAndMigratesLegacyAccounts() async throws {
        let (store, prefix) = makeIsolatedNativeMigrationStore()
        let dpAccount = UUID()
        let legacyAccount = UUID()
        try await store.save("dp", service: .backuppw, account: dpAccount)
        try addRawNativeItem(
            "legacy",
            servicePrefix: prefix,
            service: .backuppw,
            account: legacyAccount,
            dataProtection: false
        )

        let accounts = try await store.listAccounts(service: .backuppw)

        XCTAssertTrue(accounts.contains(dpAccount))
        XCTAssertTrue(accounts.contains(legacyAccount))
        XCTAssertEqual(Set(accounts).count, accounts.count)
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .backuppw,
                account: legacyAccount,
                dataProtection: true
            ).data,
            Data("legacy".utf8)
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .backuppw,
                account: legacyAccount,
                dataProtection: false
            ).status,
            errSecItemNotFound
        )
    }

    func testNativeMacMigrationUsesProductionAccessGroupSemantics() async throws {
        guard let accessGroup = try isolatedNativeAccessGroup() else {
            throw XCTSkip("签名测试宿主未能解析 Keychain access group")
        }
        let (store, prefix) = makeIsolatedNativeMigrationStore(accessGroup: accessGroup)
        let account = UUID()
        try addRawNativeItem(
            "legacy-with-access-group",
            servicePrefix: prefix,
            service: .masterpw,
            account: account,
            dataProtection: false,
            accessGroup: accessGroup
        )

        let value = try await store.read(service: .masterpw, account: account)

        XCTAssertEqual(value, "legacy-with-access-group")
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: true,
                accessGroup: accessGroup
            ).data,
            Data("legacy-with-access-group".utf8)
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: false,
                accessGroup: accessGroup
            ).status,
            errSecItemNotFound
        )
    }

    func testNativeMacMigrationFindsLegacyItemSavedBeforeAccessGroupResolved() async throws {
        guard let accessGroup = try isolatedNativeAccessGroup() else {
            throw XCTSkip("签名测试宿主未能解析 Keychain access group")
        }
        let (store, prefix) = makeIsolatedNativeMigrationStore(accessGroup: accessGroup)
        let account = UUID()
        // 旧版 seed-probe 在 legacy Keychain 中取不到 group 时，生产 Store 会以 nil 保存。
        try addRawNativeItem(
            "legacy-before-group-resolution",
            servicePrefix: prefix,
            service: .masterpw,
            account: account,
            dataProtection: false,
            accessGroup: nil
        )

        let value = try await store.read(service: .masterpw, account: account)

        XCTAssertEqual(value, "legacy-before-group-resolution")
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: true,
                accessGroup: accessGroup
            ).data,
            Data("legacy-before-group-resolution".utf8)
        )
        XCTAssertEqual(
            rawNativeStatus(
                servicePrefix: prefix,
                service: .masterpw,
                account: account,
                dataProtection: false,
                accessGroup: nil
            ).status,
            errSecItemNotFound
        )
    }

    /// 用唯一测试 Service 探测签名宿主的默认 access group；不调用生产 seed-probe，
    /// 也不读写 `com.apirelay.keychain.*` 生产命名空间。
    private func isolatedNativeAccessGroup() throws -> String? {
        let service = "com.apirelay.keychain.tests.access-group-probe.\(UUID().uuidString)"
        let account = UUID().uuidString
        var match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let deleteMatch = match
        defer { SecItemDelete(deleteMatch as CFDictionary) }

        var add = match
        add[kSecValueData as String] = Data([0])
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ApiRelayError.keychainFailure(addStatus)
        }

        match[kSecReturnAttributes as String] = true
        match[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let readStatus = SecItemCopyMatching(match as CFDictionary, &result)
        guard readStatus == errSecSuccess else {
            throw ApiRelayError.keychainFailure(readStatus)
        }
        return (result as? [String: Any])?[kSecAttrAccessGroup as String] as? String
    }

    private func makeIsolatedNativeMigrationStore(
        accessGroup: String? = nil
    ) -> (KeychainStore, String) {
        let prefix = "com.apirelay.keychain.tests.dp-migration.\(UUID().uuidString)"
        isolatedNativeMigrationPrefixes.append((prefix, accessGroup))
        return (
            KeychainStore.makeForTests(
                disableSynchronizable: true,
                accessGroup: accessGroup,
                servicePrefix: prefix
            ),
            prefix
        )
    }

    private func rawServiceName(prefix: String, service: KeychainService) -> String {
        switch service {
        case .keys: return "\(prefix).keys"
        case .admin: return "\(prefix).admin"
        case .masterpw: return "\(prefix).masterpw"
        case .backuppw: return "\(prefix).backuppw"
        }
    }

    private func addRawNativeItem(
        _ value: String,
        servicePrefix: String,
        service: KeychainService,
        account: UUID,
        dataProtection: Bool,
        accessGroup: String? = nil
    ) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: rawServiceName(prefix: servicePrefix, service: service),
            kSecAttrAccount as String: account.uuidString,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        query[kSecUseDataProtectionKeychain as String] = dataProtection
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
    }

    private func rawNativeStatus(
        servicePrefix: String,
        service: KeychainService,
        account: UUID,
        dataProtection: Bool,
        accessGroup: String? = nil
    ) -> (status: OSStatus, data: Data?) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: rawServiceName(prefix: servicePrefix, service: service),
            kSecAttrAccount as String: account.uuidString,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecUseDataProtectionKeychain as String] = dataProtection
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    private func deleteRawNativeItems(
        servicePrefix: String,
        service: KeychainService,
        dataProtection: Bool,
        accessGroup: String? = nil
    ) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: rawServiceName(prefix: servicePrefix, service: service),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        query[kSecUseDataProtectionKeychain as String] = dataProtection
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        SecItemDelete(query as CFDictionary)
    }
    #endif
}
