@preconcurrency import XCTest
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

    func testSaltDiffersAcrossSets() async throws {
        try await sut.setPassword("same-password")
        let first = try await keychain.read(
            service: .masterpw,
            account: KeychainStore.masterPasswordAccount
        )
        try await sut.setPassword("same-password")
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
}
