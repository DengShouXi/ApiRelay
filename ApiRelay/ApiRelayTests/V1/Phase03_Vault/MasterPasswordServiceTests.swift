@preconcurrency import XCTest
import Security
@testable import ApiRelay

@MainActor
final class MasterPasswordServiceTests: XCTestCase {
    private var keychain: KeychainStore!
    private var sut: MasterPasswordService!

    override func setUp() async throws {
        keychain = KeychainStore.makeForTests(disableSynchronizable: false)
        sut = MasterPasswordService(keychain: keychain, calibratedIterations: 12_000)
        try? await sut.reset()
    }

    override func tearDown() async throws {
        try? await sut.reset()
    }

    func testVerifyCorrectAndWrong() async throws {
        try await sut.setPassword("correct-horse")
        let ok = try await sut.verify("correct-horse")
        let bad = try await sut.verify("wrong-pass")
        XCTAssertTrue(ok)
        XCTAssertFalse(bad)
    }

    func testVerifyAndChangeUseSameTrimmingAsCreation() async throws {
        try await sut.setPassword("  original-pass  ")

        let verifiesCanonicalPassword = try await sut.verify("original-pass")
        let verifiesPaddedPassword = try await sut.verify("  original-pass\n")
        XCTAssertTrue(verifiesCanonicalPassword)
        XCTAssertTrue(verifiesPaddedPassword)

        try await sut.changePassword(current: " original-pass ", new: "  replacement-pass  ")
        let rejectsOldPassword = try await sut.verify("original-pass")
        let verifiesReplacement = try await sut.verify("replacement-pass")
        let verifiesPaddedReplacement = try await sut.verify(" replacement-pass\n")
        XCTAssertFalse(rejectsOldPassword)
        XCTAssertTrue(verifiesReplacement)
        XCTAssertTrue(verifiesPaddedReplacement)
    }

    func testSaltDiffersAcrossSets() async throws {
        try await sut.setPassword("same-password")
        let first = try await keychain.read(
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )
        try await sut.changePassword(current: "same-password", new: "same-password")
        let second = try await keychain.read(
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )
        XCTAssertNotEqual(first, second)
    }

    func testResetInvalidatesOldPassword() async throws {
        try await sut.setPassword("old-secret")
        try await sut.reset()
        let isSet = try await sut.isSet()
        XCTAssertFalse(isSet)
        try await sut.setPassword("new-secret")
        let oldOk = try await sut.verify("old-secret")
        let newOk = try await sut.verify("new-secret")
        XCTAssertFalse(oldOk)
        XCTAssertTrue(newOk)
    }

    func testChangePasswordRejectsWrongCurrent() async throws {
        try await sut.setPassword("old-pass")
        do {
            try await sut.changePassword(current: "nope", new: "new-pass")
            XCTFail("expected authenticationFailed")
        } catch ApiRelayError.authenticationFailed {
        }
        let stillOld = try await sut.verify("old-pass")
        XCTAssertTrue(stillOld)
    }

    func testConsecutiveFailuresDelayRetry() async throws {
        try await sut.setPassword("abcd")
        let first = try await sut.verify("xxxx")
        let second = try await sut.verify("xxxx")
        let third = try await sut.verify("xxxx")
        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertFalse(third)
        do {
            _ = try await sut.verify("xxxx")
            XCTFail("expected retry delay")
        } catch ApiRelayError.masterPasswordRetryDelayed {
        }
    }

    func testFailureCounterAndDelaySurviveServiceRelaunch() async throws {
        let clock = TestDateClock(Date(timeIntervalSince1970: 1_700_000_000))
        let first = MasterPasswordService(
            keychain: keychain,
            calibratedIterations: 12_000,
            now: { clock.read() }
        )
        try await first.setPassword("persistent-pass")
        let firstFailure = try await first.verify("wrong-pass")
        let secondFailure = try await first.verify("wrong-pass")
        XCTAssertFalse(firstFailure)
        XCTAssertFalse(secondFailure)

        let relaunched = MasterPasswordService(
            keychain: keychain,
            calibratedIterations: 12_000,
            now: { clock.read() }
        )
        let thirdFailure = try await relaunched.verify("wrong-pass")
        XCTAssertFalse(thirdFailure)
        do {
            _ = try await relaunched.verify("persistent-pass")
            XCTFail("expected persisted retry delay")
        } catch ApiRelayError.masterPasswordRetryDelayed {
        }

        clock.advance(by: 3)
        let succeededAfterDelay = try await relaunched.verify("persistent-pass")
        XCTAssertTrue(succeededAfterDelay)
        let afterSuccessRelaunch = MasterPasswordService(
            keychain: keychain,
            calibratedIterations: 12_000,
            now: { clock.read() }
        )
        let succeededAfterRelaunch = try await afterSuccessRelaunch.verify("persistent-pass")
        XCTAssertTrue(succeededAfterRelaunch)
    }

    func testTenFailuresDurablyLockUntilDeviceRecoveryResetsMaterial() async throws {
        let clock = TestDateClock(Date(timeIntervalSince1970: 1_700_000_000))
        let service = MasterPasswordService(
            keychain: keychain,
            calibratedIterations: 12_000,
            now: { clock.read() }
        )
        try await service.setPassword("correct-password")
        for attempt in 1...9 {
            let accepted = try await service.verify("wrong-password")
            XCTAssertFalse(accepted, "attempt \(attempt)")
            clock.advance(by: 61)
        }
        do {
            _ = try await service.verify("wrong-password")
            XCTFail("expected durable lock on the tenth failure")
        } catch ApiRelayError.masterPasswordLocked {
        }

        let relaunched = MasterPasswordService(
            keychain: keychain,
            calibratedIterations: 12_000,
            now: { clock.read() }
        )
        do {
            _ = try await relaunched.verify("correct-password")
            XCTFail("relaunch must not clear the failure ceiling")
        } catch ApiRelayError.masterPasswordLocked {
        }

        try await relaunched.reset()
        try await relaunched.setPassword("replacement-password")
        let replacementAccepted = try await relaunched.verify("replacement-password")
        XCTAssertTrue(replacementAccepted)
    }

    func testConcurrentVerificationCannotLoseRetryCounterUpdate() async throws {
        let legacy = "v1:12000:AAECAwQFBgcICQoLDA0ODw==:eE3ZGF78bGAUg2obc6IHNl95t7Cp0cMaGH3bGDQTGM8="
        let latch = BlockingReadLatch()
        let blockingKeychain = BlockingMasterPasswordKeychain(payload: legacy, latch: latch)
        let service = MasterPasswordService(keychain: blockingKeychain, calibratedIterations: 12_000)

        async let firstAttempt = service.verify("wrong-password")
        await latch.waitUntilReadStarted()

        do {
            _ = try await service.verify("another-wrong-password")
            XCTFail("a concurrent verifier must not enter the same read/write transaction")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "masterPassword")
            XCTAssertEqual(reason, "stale_concurrent")
        }

        latch.releaseRead()
        let firstAccepted = try await firstAttempt
        XCTAssertFalse(firstAccepted)

        // The rejected concurrent call did not overwrite or reset the first
        // durable failure update; two further sequential failures reach delay.
        let secondSequentialAccepted = try await service.verify("wrong-password")
        let thirdSequentialAccepted = try await service.verify("wrong-password")
        XCTAssertFalse(secondSequentialAccepted)
        XCTAssertFalse(thirdSequentialAccepted)
        do {
            _ = try await service.verify("legacy-pass")
            XCTFail("the third persisted failure must arm retry delay")
        } catch ApiRelayError.masterPasswordRetryDelayed {
        }
    }

    func testSuccessfulLegacyV1VerificationUpgradesPayloadWithoutChangingPassword() async throws {
        let legacy = "v1:12000:AAECAwQFBgcICQoLDA0ODw==:eE3ZGF78bGAUg2obc6IHNl95t7Cp0cMaGH3bGDQTGM8="
        try await keychain.save(
            legacy,
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )
        let service = MasterPasswordService(keychain: keychain, calibratedIterations: 12_000)

        let legacyAccepted = try await service.verify("legacy-pass")
        XCTAssertTrue(legacyAccepted)
        let upgraded = try await keychain.read(
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )
        XCTAssertTrue(upgraded.hasPrefix("v2:"))
        let upgradedAccepted = try await service.verify("legacy-pass")
        XCTAssertTrue(upgradedAccepted)
    }

    func testPolicyEvaluateReportsEachRule() {
        let empty = MasterPasswordPolicy.evaluate(password: "", confirm: "")
        XCTAssertEqual(empty.trimmedLength, 0)
        XCTAssertFalse(empty.meetsMinimumLength)
        XCTAssertTrue(empty.confirmMatches)
        XCTAssertFalse(empty.canSave)

        let tooShort = MasterPasswordPolicy.evaluate(password: "ab", confirm: "ab")
        XCTAssertEqual(tooShort.trimmedLength, 2)
        XCTAssertFalse(tooShort.meetsMinimumLength)
        XCTAssertTrue(tooShort.confirmMatches)

        let mismatch = MasterPasswordPolicy.evaluate(password: "abcd", confirm: "abce")
        XCTAssertTrue(mismatch.meetsMinimumLength)
        XCTAssertFalse(mismatch.confirmMatches)
        XCTAssertFalse(mismatch.canSave)

        let bothFail = MasterPasswordPolicy.evaluate(password: "ab", confirm: "cd")
        XCTAssertFalse(bothFail.meetsMinimumLength)
        XCTAssertFalse(bothFail.confirmMatches)

        let ok = MasterPasswordPolicy.evaluate(password: "  abcd  ", confirm: "abcd")
        XCTAssertEqual(ok.trimmedLength, 4)
        XCTAssertTrue(ok.meetsMinimumLength)
        XCTAssertTrue(ok.confirmMatches)
        XCTAssertTrue(ok.canSave)
    }

    func testTooShortIsRejectedWithExistingReason() async throws {
        do {
            try await sut.setPassword("abc")
            XCTFail("expected too_short")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "masterPassword")
            XCTAssertEqual(reason, "too_short")
        }
    }

    func testResetDoesNotDeleteKeysAdminOrBackupPassphrase() async throws {
        try await sut.setPassword("test-pass-word")
        let keyId = UUID()
        let adminId = UUID()
        try await keychain.save("sk-keep-local", service: .keys, account: keyId)
        try await keychain.save("admin-keep-local", service: .admin, account: adminId)
        try await keychain.save("backup-keep-local", service: .backuppw, account: KeychainStore.backupPassphraseAccount)
        let store = keychain!
        addTeardownBlock {
            try? await store.delete(service: .keys, account: keyId)
            try? await store.delete(service: .admin, account: adminId)
            try? await store.delete(
                service: .backuppw,
                account: KeychainStore.backupPassphraseAccount
            )
        }
        try await sut.reset()
        let isSet = try await sut.isSet()
        XCTAssertFalse(isSet)
        let keptKey = try await keychain.read(service: .keys, account: keyId)
        let keptAdmin = try await keychain.read(service: .admin, account: adminId)
        let keptBackup = try await keychain.read(
            service: .backuppw,
            account: KeychainStore.backupPassphraseAccount
        )
        XCTAssertEqual(keptKey, "sk-keep-local")
        XCTAssertEqual(keptAdmin, "admin-keep-local")
        XCTAssertEqual(keptBackup, "backup-keep-local")
    }

    func testMaterialStatusUnsetSetAndUnreadable() async throws {
        let unset = await sut.materialStatus()
        XCTAssertEqual(unset, .unset)
        try await sut.setPassword("test-pass-word")
        let set = await sut.materialStatus()
        XCTAssertEqual(set, .set)
        let failing = UnreadableMasterpwKeychain()
        let unread = MasterPasswordService(keychain: failing, calibratedIterations: 1_000)
        let unreadStatus = await unread.materialStatus()
        XCTAssertEqual(unreadStatus, .unreadable)
        XCTAssertNotEqual(unreadStatus, .unset)
        do {
            _ = try await unread.isSet()
            XCTFail("expected keychainFailure")
        } catch ApiRelayError.keychainFailure {
        }
    }

    func testMalformedOrUnboundedStoredPayloadIsUnreadableNotWrongPassword() async throws {
        try await keychain.save(
            "v1:4294967295:AQ==:AQ==",
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )

        let status = await sut.materialStatus()
        XCTAssertEqual(status, .unreadable)
        do {
            _ = try await sut.isSet()
            XCTFail("expected material_unreadable")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "masterPassword")
            XCTAssertEqual(reason, "material_unreadable")
        }
        do {
            _ = try await sut.verify("any-password")
            XCTFail("expected material_unreadable")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "masterPassword")
            XCTAssertEqual(reason, "material_unreadable")
        }
    }

    func testChangePasswordDoesNotOverwriteOnWrongCurrent() async throws {
        try await sut.setPassword("keep-old-pass")
        do {
            try await sut.changePassword(current: "wrong-old-pass", new: "brand-new-pass")
            XCTFail("expected authenticationFailed")
        } catch ApiRelayError.authenticationFailed {
        }
        let stillOld = try await sut.verify("keep-old-pass")
        let overwritten = try await sut.verify("brand-new-pass")
        XCTAssertTrue(stillOld)
        XCTAssertFalse(overwritten)
    }

    func testChangePasswordPageInvalidatedAfterVerificationDoesNotReplaceMaterial() async throws {
        let source = FakeKeychain()
        let setup = MasterPasswordService(keychain: source, calibratedIterations: 12_000)
        try await setup.setPassword("keep-old-pass")
        let originalPayload = try await source.read(
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )
        let latch = BlockingReadLatch()
        // Read 1 verifies and PBKDF-checks the old password. Read 2 is the final
        // material-status await immediately before deriving/committing the new one.
        let blockingKeychain = BlockingMasterPasswordKeychain(
            payload: originalPayload,
            latch: latch,
            blockReadOrdinal: 2
        )
        let service = MasterPasswordService(keychain: blockingKeychain, calibratedIterations: 12_000)
        let lease = AppPasswordPageLease(
            target: .masterPassword,
            currentPolicy: .masterPassword
        )
        let token = try XCTUnwrap(lease.begin())
        let request = AppPasswordSubmitContext(lease: lease, token: token)

        let change = Task {
            try await service.changePassword(
                current: "keep-old-pass",
                new: "must-not-be-written",
                committing: { operation in
                    try request.commit(.materialWrite, operation: operation)
                }
            )
        }
        await latch.waitUntilReadStarted()
        lease.invalidate()
        latch.releaseRead()

        do {
            try await change.value
            XCTFail("an invalidated settings page must not replace material")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "stale_page_request")
        }
        let oldPasswordStillWorks = try await service.verify("keep-old-pass")
        let newPasswordWasRejected = try await service.verify("must-not-be-written")
        XCTAssertTrue(oldPasswordStillWorks)
        XCTAssertFalse(newPasswordWasRejected)
    }

    func testSetPasswordDoesNotOverwriteExistingMaterial() async throws {
        try await sut.setPassword("keep-original-pass")
        do {
            try await sut.setPassword("overwrite-attempt")
            XCTFail("expected already_set")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "masterPassword")
            XCTAssertEqual(reason, "already_set")
        }
        let keptOriginal = try await sut.verify("keep-original-pass")
        let overwritten = try await sut.verify("overwrite-attempt")
        XCTAssertTrue(keptOriginal)
        XCTAssertFalse(overwritten)
    }

    func testSetPasswordDoesNotWriteWhenMaterialUnreadable() async throws {
        let unread = MasterPasswordService(
            keychain: UnreadableMasterpwKeychain(),
            calibratedIterations: 1_000
        )
        do {
            try await unread.setPassword("test-pass-word")
            XCTFail("expected material_unreadable")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "masterPassword")
            XCTAssertEqual(reason, "material_unreadable")
        }
        let unreadStatus = await unread.materialStatus()
        XCTAssertEqual(unreadStatus, .unreadable)
    }

    func testConcurrentSetPasswordDoesNotLeaveMixedMaterial() async throws {
        try? await sut.reset()
        let service = sut!
        async let firstOutcome: PasswordSetOutcome = {
            do {
                try await service.setPassword("first-window-pass")
                return .success
            } catch let ApiRelayError.validationFailed(_, reason) {
                return .failureReason(reason)
            } catch {
                return .failureReason("other")
            }
        }()
        async let secondOutcome: PasswordSetOutcome = {
            do {
                try await service.setPassword("second-window-pass")
                return .success
            } catch let ApiRelayError.validationFailed(_, reason) {
                return .failureReason(reason)
            } catch {
                return .failureReason("other")
            }
        }()
        let results = [await firstOutcome, await secondOutcome]
        let successes = results.filter { if case .success = $0 { return true } else { return false } }
        let failures = results.filter { if case .failureReason = $0 { return true } else { return false } }
        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(failures.count, 1)
        if case let .failureReason(reason) = failures[0] {
            XCTAssertTrue(reason == "already_set" || reason == "stale_concurrent")
        }
        let firstKept = try await service.verify("first-window-pass")
        let secondKept = try await service.verify("second-window-pass")
        XCTAssertEqual([firstKept, secondKept].filter(\.self).count, 1)
    }

    func testResetExpectedRevisionDoesNotDeleteAfterLaterChange() async throws {
        try await sut.setPassword("original-pass-word")
        let snapshot = await sut.materialRevision()
        try await sut.changePassword(current: "original-pass-word", new: "other-window-pass")
        do {
            try await sut.reset(expectedRevision: snapshot)
            XCTFail("expected stale_concurrent")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "stale_concurrent")
        }
        let otherKept = try await sut.verify("other-window-pass")
        let originalKept = try await sut.verify("original-pass-word")
        XCTAssertTrue(otherKept)
        XCTAssertFalse(originalKept)
    }

    func testSetMaterialLeaseBlocksResetInsideCommit() async throws {
        try await sut.setPassword("keep-me-pass")
        let snapshot = await sut.materialRevision()
        let service = sut!
        try await service.withUnchangedSetMaterial(expectedRevision: snapshot) {
            do {
                try await service.reset(expectedRevision: snapshot)
                XCTFail("expected stale_concurrent")
            } catch let ApiRelayError.validationFailed(_, reason) {
                XCTAssertEqual(reason, "stale_concurrent")
            }
        }
        let kept = try await sut.verify("keep-me-pass")
        XCTAssertTrue(kept)
        let after = await sut.materialRevision()
        XCTAssertEqual(after, snapshot)
    }
}

private enum PasswordSetOutcome: Sendable {
    case success
    case failureReason(String)
}

actor UnreadableMasterpwKeychain: KeychainStoring {
    func save(_ secret: String, service: KeychainService, account: UUID) throws {}

    func read(service: KeychainService, account: UUID) throws -> String {
        throw ApiRelayError.keychainFailure(-50)
    }

    func delete(service: KeychainService, account: UUID) throws {}

    func listAccounts(service: KeychainService) throws -> [UUID] { [] }
}

private final class TestDateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func read() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class BlockingReadLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var readStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private let release = DispatchSemaphore(value: 0)

    func markReadStartedAndWait() {
        lock.lock()
        readStarted = true
        let waiter = startWaiter
        startWaiter = nil
        lock.unlock()
        waiter?.resume()
        release.wait()
    }

    func waitUntilReadStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if readStarted {
                lock.unlock()
                continuation.resume()
            } else {
                startWaiter = continuation
                lock.unlock()
            }
        }
    }

    func releaseRead() {
        release.signal()
    }
}

private actor BlockingMasterPasswordKeychain: KeychainStoring {
    private var payload: String
    private let latch: BlockingReadLatch
    private let blockReadOrdinal: Int
    private var readCount = 0

    init(payload: String, latch: BlockingReadLatch, blockReadOrdinal: Int = 1) {
        self.payload = payload
        self.latch = latch
        self.blockReadOrdinal = blockReadOrdinal
    }

    func save(_ secret: String, service: KeychainService, account: UUID) throws {
        switch service {
        case .masterpw:
            payload = secret
        default:
            return
        }
    }

    func read(service: KeychainService, account: UUID) throws -> String {
        switch service {
        case .masterpw:
            break
        default:
            throw ApiRelayError.keychainFailure(errSecItemNotFound)
        }
        readCount += 1
        if readCount == blockReadOrdinal {
            latch.markReadStartedAndWait()
        }
        return payload
    }

    func delete(service: KeychainService, account: UUID) throws {}

    func listAccounts(service: KeychainService) throws -> [UUID] { [] }
}
