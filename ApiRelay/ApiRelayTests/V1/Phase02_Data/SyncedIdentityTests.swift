@preconcurrency import XCTest
@testable import ApiRelay

final class SyncedIdentityTests: XCTestCase {
    func testLosersToPruneRequiresUniqueWinner() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let stale = ReplicaStub(updatedAt: older, isDeleted: false, fingerprint: "a")
        let fresh = ReplicaStub(updatedAt: newer, isDeleted: false, fingerprint: "b")
        let losers = SyncedIdentity.losersToPrune([stale, fresh]) { stub in
            SyncedIdentity.ReplicaRank(
                updatedAt: stub.updatedAt,
                isDeleted: stub.isDeleted,
                fingerprint: stub.fingerprint
            )
        }
        XCTAssertEqual(losers.count, 1)
        XCTAssertTrue(losers[0] === stale)
    }

    func testIdenticalReplicasAreNotPruned() {
        let stamp = Date(timeIntervalSince1970: 100)
        let a = ReplicaStub(updatedAt: stamp, isDeleted: false, fingerprint: "same")
        let b = ReplicaStub(updatedAt: stamp, isDeleted: false, fingerprint: "same")
        let losers = SyncedIdentity.losersToPrune([a, b]) { stub in
            SyncedIdentity.ReplicaRank(
                updatedAt: stub.updatedAt,
                isDeleted: stub.isDeleted,
                fingerprint: stub.fingerprint
            )
        }
        XCTAssertTrue(losers.isEmpty)
    }

    func testTombstoneOutranksLiveWhenTimestampsMatch() {
        let stamp = Date(timeIntervalSince1970: 100)
        let live = ReplicaStub(updatedAt: stamp, isDeleted: false, fingerprint: "live")
        let trash = ReplicaStub(updatedAt: stamp, isDeleted: true, fingerprint: "trash")
        let winner = SyncedIdentity.winner(in: [live, trash]) { stub in
            SyncedIdentity.ReplicaRank(
                updatedAt: stub.updatedAt,
                isDeleted: stub.isDeleted,
                fingerprint: stub.fingerprint
            )
        }
        XCTAssertTrue(winner === trash)
    }

    func testDateStampIsIntegerMicrosecondsWithoutDecimalPoint() {
        XCTAssertEqual(SyncedIdentity.dateStamp(nil), "")
        XCTAssertEqual(SyncedIdentity.dateStamp(Date(timeIntervalSince1970: 100)), "100000000")
        XCTAssertEqual(SyncedIdentity.dateStamp(Date(timeIntervalSince1970: 100.5)), "100500000")
        let stamp = SyncedIdentity.dateStamp(Date(timeIntervalSince1970: 1.5))
        XCTAssertEqual(stamp, "1500000")
    }

    func testDecimalStampUsesPOSIXPointNotCurrentLocale() {
        let value = Decimal(string: "12.34", locale: Locale(identifier: "en_US_POSIX"))!
        XCTAssertEqual(SyncedIdentity.decimalStamp(value), "12.34")
        XCTAssertEqual(SyncedIdentity.decimalStamp(nil), "")
        let french = NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(SyncedIdentity.decimalStamp(value), "12.34")
        if french.contains(",") {
            XCTAssertNotEqual(SyncedIdentity.decimalStamp(value), french)
        }
    }
}

private final class ReplicaStub {
    var updatedAt: Date
    var isDeleted: Bool
    var fingerprint: String

    init(updatedAt: Date, isDeleted: Bool, fingerprint: String) {
        self.updatedAt = updatedAt
        self.fingerprint = fingerprint
        self.isDeleted = isDeleted
    }
}
