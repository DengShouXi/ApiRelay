@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class MasterPasswordServiceTests: XCTestCase {
    private var keychain: KeychainStore!
    private var sut: MasterPasswordService!

    override func setUp() async throws {
        keychain = KeychainStore(accessGroup: nil)
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
}
