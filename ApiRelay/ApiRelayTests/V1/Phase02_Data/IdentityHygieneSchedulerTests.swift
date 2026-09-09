@preconcurrency import XCTest
@testable import ApiRelay

final class IdentityHygieneSchedulerTests: XCTestCase {
    func testRapidRequestsRunWorkOnce() async {
        let scheduler = IdentityHygieneScheduler(delay: .milliseconds(80))
        let counter = Counter()
        async let first: Void = scheduler.request { await counter.increment() }
        async let second: Void = scheduler.request { await counter.increment() }
        _ = await (first, second)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testCloudImportHygieneCoalescesHandleImportSucceeded() async {
        let counter = Counter()
        let hygiene = CloudImportIdentityHygiene(delay: .milliseconds(80)) {
            await counter.increment()
        }
        async let first: Void = hygiene.handleImportSucceeded()
        async let second: Void = hygiene.handleImportSucceeded()
        _ = await (first, second)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testRunIsolatedContinuesAfterAStepFails() async {
        let counter = Counter()
        enum Boom: Error { case fail }
        await IdentityHygieneLog.runIsolated(source: .startup, steps: [
            (.account, { throw Boom.fail }),
            (.key, { await counter.increment() }),
        ])
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testErrorTypeNameOmitsUserInfoAndDescription() {
        let err = NSError(
            domain: "TestDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "sk-secret-must-not-appear-in-logs-12345"]
        )
        let name = IdentityHygieneLog.typeName(err)
        XCTAssertTrue(name.contains("TestDomain"))
        XCTAssertTrue(name.contains("42"))
        XCTAssertFalse(name.contains("sk-"))
        XCTAssertFalse(name.contains("must-not-appear"))
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
