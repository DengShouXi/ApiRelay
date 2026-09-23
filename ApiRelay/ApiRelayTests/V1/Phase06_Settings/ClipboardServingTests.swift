@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class ClipboardServingTests: XCTestCase {
    private final class PasteboardSpy: @unchecked Sendable {
        var value: String?
        var changeCount = 0
        var clearCount = 0
        var lastLocalOnly: Bool?
        var failWrites = false

        func write(_ value: String, localOnly: Bool) -> Int {
            self.value = value
            lastLocalOnly = localOnly
            changeCount += 1
            return changeCount
        }

        func clear() {
            value = nil
            clearCount += 1
            changeCount += 1
        }
    }

    func testCancelledOldTimerCannotClearNewClipboardWrite() async throws {
        let spy = PasteboardSpy()
        let sut = makeClipboard(spy)

        try await sut.write("first", expiresAfter: 0.04, localOnly: false)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await sut.write("second", expiresAfter: 1, localOnly: true)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(spy.value, "second")
        XCTAssertEqual(spy.clearCount, 0, "被取消的旧计时器不得提前清除最新一次复制")
        XCTAssertEqual(spy.lastLocalOnly, true)
        await sut.clearIfStillOurs()
    }

    func testTimerDoesNotClearContentCopiedLaterByAnotherApp() async throws {
        let spy = PasteboardSpy()
        let sut = makeClipboard(spy)

        try await sut.write("ours", expiresAfter: 0.03, localOnly: false)
        spy.value = "someone-elses-copy"
        spy.changeCount += 1
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(spy.value, "someone-elses-copy")
        XCTAssertEqual(spy.clearCount, 0, "不得删除用户随后从其它 App 复制的内容")
    }

    func testTimerDoesNotClearIdenticalContentCopiedLaterByAnotherApp() async throws {
        let spy = PasteboardSpy()
        let sut = makeClipboard(spy)

        try await sut.write("same-secret", expiresAfter: 0.03, localOnly: false)
        // 文本相同也可能是另一个 App 的新写入；changeCount 才是所有权边界。
        spy.value = "same-secret"
        spy.changeCount += 1
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(spy.value, "same-secret")
        XCTAssertEqual(spy.clearCount, 0)
    }

    func testZeroSecondAutoClearReallyClearsImmediately() async throws {
        let spy = PasteboardSpy()
        let sut = makeClipboard(spy)

        try await sut.write("clear-now", expiresAfter: 0, localOnly: false)

        XCTAssertNil(spy.value)
        XCTAssertEqual(spy.clearCount, 1)
    }

    func testDisabledAutoClearDoesNotScheduleADeletion() async throws {
        let spy = PasteboardSpy()
        let sut = makeClipboard(spy)

        try await sut.write("keep", expiresAfter: nil, localOnly: false)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(spy.value, "keep")
        XCTAssertEqual(spy.clearCount, 0, "disabled auto-clear must not schedule a timer")
        await sut.clearIfStillOurs()
        XCTAssertNil(spy.value, "full erase must still clear the exact item written by this app")
        XCTAssertEqual(spy.clearCount, 1, "ownership is one-shot")
    }

    func testSealedStorageGateRejectsClipboardWriteBeforePasteboardMutation() async throws {
        let spy = PasteboardSpy()
        let mutationGate = StorageMutationGate(erasePending: true)
        let sut = SecureClipboard(
            mutationGate: mutationGate,
            pasteboardWriter: { value, _, localOnly in
                .success(changeCount: spy.write(value, localOnly: localOnly))
            },
            pasteboardCompareAndClear: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            }
        )

        do {
            try await sut.write("must-not-leak", expiresAfter: nil, localOnly: true)
            XCTFail("a clipboard write starting after erase sealing must fail")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }

        XCTAssertNil(spy.value)
        XCTAssertEqual(spy.changeCount, 0)
    }

    func testFailedReplacementWriteKeepsPreviousCleanupArmed() async throws {
        let spy = PasteboardSpy()
        let sut = SecureClipboard(
            pasteboardWriter: { value, _, localOnly in
                guard !spy.failWrites else {
                    return .failure(lastAttemptChangeCount: nil)
                }
                return .success(changeCount: spy.write(value, localOnly: localOnly))
            },
            pasteboardCompareAndClear: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            }
        )

        try await sut.write("first-sensitive", expiresAfter: 0.04, localOnly: false)
        spy.failWrites = true

        do {
            try await sut.write("replacement", expiresAfter: 1, localOnly: true)
            XCTFail("failed replacement must be reported")
        } catch {
            // Expected: the original write still owns the pasteboard and its
            // original timer remains responsible for clearing it.
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(spy.value)
        XCTAssertEqual(spy.clearCount, 1)
    }

    func testFailedWriteAfterPasteboardMutationRollsBackAndRetiresOldOwnership() async throws {
        ClipboardTerminationGuard.resetForTests()
        defer { ClipboardTerminationGuard.resetForTests() }

        let spy = PasteboardSpy()
        let sut = SecureClipboard(
            pasteboardWriter: { value, _, localOnly in
                let changeCount = spy.write(value, localOnly: localOnly)
                return spy.failWrites
                    ? .failure(lastAttemptChangeCount: changeCount)
                    : .success(changeCount: changeCount)
            },
            pasteboardCompareAndClear: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            },
            pasteboardRollback: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            }
        )

        try await sut.write("previous", expiresAfter: 0.05, localOnly: false)
        XCTAssertNotNil(ClipboardTerminationGuard.armedSnapshotForTests())
        spy.failWrites = true

        do {
            try await sut.write("partially-written-secret", expiresAfter: 20, localOnly: true)
            XCTFail("partial write must be reported as a failure")
        } catch {
            // Expected. Rollback must have happened before the error escapes.
        }

        XCTAssertNil(spy.value, "a failed write must not leave its secret on the pasteboard")
        XCTAssertEqual(spy.clearCount, 1)
        XCTAssertNil(
            ClipboardTerminationGuard.armedSnapshotForTests(),
            "a mutating failure supersedes the prior termination ownership"
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(spy.clearCount, 1, "the retired old timer must not run later")
    }

    func testFailedWriteRollbackDoesNotDeleteLaterExternalWrite() async throws {
        let spy = PasteboardSpy()
        let sut = SecureClipboard(
            pasteboardWriter: { value, _, localOnly in
                let failedAttemptCount = spy.write(value, localOnly: localOnly)
                _ = spy.write("later-external-copy", localOnly: false)
                return .failure(lastAttemptChangeCount: failedAttemptCount)
            },
            pasteboardCompareAndClear: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            },
            pasteboardRollback: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            }
        )

        do {
            try await sut.write("failed-secret", expiresAfter: 10, localOnly: false)
            XCTFail("partial write must be reported as a failure")
        } catch {
            // Expected. The external owner changed the generation first.
        }

        XCTAssertEqual(spy.value, "later-external-copy")
        XCTAssertEqual(spy.clearCount, 0)
    }

    func testAtomicCompareAndClearDoesNotDeleteWriteArrivingAtCommitBoundary() async throws {
        let spy = PasteboardSpy()
        var injectReplacement = true
        let sut = SecureClipboard(
            pasteboardWriter: { value, _, localOnly in
                .success(changeCount: spy.write(value, localOnly: localOnly))
            },
            pasteboardCompareAndClear: { changeCount in
                guard spy.changeCount == changeCount else { return false }

                // Deterministically reproduce the old matcher/clearer gap: a
                // different owner writes after ownership was observed but before
                // deletion commits. The combined seam rechecks at the commit
                // boundary and must preserve that replacement.
                if injectReplacement {
                    injectReplacement = false
                    _ = spy.write("later-external-copy", localOnly: false)
                }
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            }
        )

        try await sut.write("ours", expiresAfter: 0, localOnly: false)

        XCTAssertEqual(spy.value, "later-external-copy")
        XCTAssertEqual(spy.clearCount, 0)
    }

    func testStaleCleanupCannotDisarmNewerTerminationGuard() {
        ClipboardTerminationGuard.resetForTests()
        defer { ClipboardTerminationGuard.resetForTests() }

        ClipboardTerminationGuard.arm(changeCount: 11, generation: 1)
        ClipboardTerminationGuard.arm(changeCount: 22, generation: 2)
        ClipboardTerminationGuard.disarm(ifOwnedByGeneration: 1)

        let snapshot = ClipboardTerminationGuard.armedSnapshotForTests()
        XCTAssertEqual(snapshot?.changeCount, 22)
        XCTAssertEqual(snapshot?.generation, 2)
    }

    private func makeClipboard(_ spy: PasteboardSpy) -> SecureClipboard {
        SecureClipboard(
            pasteboardWriter: { value, _, localOnly in
                .success(changeCount: spy.write(value, localOnly: localOnly))
            },
            pasteboardCompareAndClear: { changeCount in
                guard spy.changeCount == changeCount else { return false }
                spy.clear()
                return true
            }
        )
    }
}
