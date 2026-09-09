@preconcurrency import XCTest
@testable import ApiRelay

final class DurationOptionListTests: XCTestCase {
    func testEmptyJSONIsUserClearedNotUninitialized() {
        XCTAssertEqual(DurationOptionList.decode("[]"), [])
        XCTAssertNil(DurationOptionList.decode(nil))
        XCTAssertEqual(DurationOptionList.encode([]), "[]")
    }

    func testSeedFillsFactoryAndKeepsExistingCurrent() {
        let seeded = DurationOptionList.seedIfNeeded(stored: nil, current: 300, factory: [0, 60])
        XCTAssertEqual(seeded, [0, 60, 300])
        XCTAssertEqual(
            DurationOptionList.seedIfNeeded(stored: [], current: 300, factory: [0, 60]),
            []
        )
    }

    func testAddSelectsExistingAndRejectsSixth() {
        let first = DurationOptionList.adding(60, to: [0, 60])
        XCTAssertEqual(first, .selectedExisting(options: [0, 60], selected: 60))

        var options = [0, 30, 60, 120]
        switch DurationOptionList.adding(7200, to: options) {
        case .added(let next, let selected):
            options = next
            XCTAssertEqual(selected, 7200)
        default:
            XCTFail("should add")
        }
        XCTAssertEqual(DurationOptionList.adding(1, to: options), .atCapacity)
    }

    func testRemoveLastClearsSelection() {
        let result = DurationOptionList.removing(60, from: [60], selected: 60)
        XCTAssertEqual(result.options, [])
        XCTAssertNil(result.selected)
    }

    func testRemoveSelectedFallsBackToFirstRemaining() {
        let result = DurationOptionList.removing(60, from: [0, 60, 120], selected: 60)
        XCTAssertEqual(result.options, [0, 120])
        XCTAssertEqual(result.selected, 0)
    }

    func testSecondsSixtyEqualsOneMinuteAndDedupes() {
        XCTAssertEqual(DurationOptionList.total(hours: 0, minutes: 0, seconds: 60), 60)
        XCTAssertEqual(
            DurationOptionList.adding(60, to: [DurationOptionList.total(hours: 0, minutes: 1, seconds: 0)]),
            .selectedExisting(options: [60], selected: 60)
        )
    }

    func testComponentsRoundTripExceptSixtySecondOverflow() {
        let parts = DurationOptionList.components(3661)
        XCTAssertEqual(parts.hours, 1)
        XCTAssertEqual(parts.minutes, 1)
        XCTAssertEqual(parts.seconds, 1)
        XCTAssertEqual(DurationOptionList.total(hours: 1, minutes: 1, seconds: 1), 3661)
    }

    func testClockFormatAndParse() {
        XCTAssertEqual(DurationOptionList.formatClock(hours: 0, minutes: 1, seconds: 0), "0:01:00")
        XCTAssertEqual(DurationOptionList.formatClock(3661), "1:01:01")
        let parsed = DurationOptionList.parseClock("2:03:04")
        XCTAssertEqual(parsed?.hours, 2)
        XCTAssertEqual(parsed?.minutes, 3)
        XCTAssertEqual(parsed?.seconds, 4)
        let minutesSeconds = DurationOptionList.parseClock("1:30")
        XCTAssertEqual(minutesSeconds?.hours, 0)
        XCTAssertEqual(minutesSeconds?.minutes, 1)
        XCTAssertEqual(minutesSeconds?.seconds, 30)
        let secondsOnly = DurationOptionList.parseClock("90")
        XCTAssertEqual(secondsOnly?.hours, 0)
        XCTAssertEqual(secondsOnly?.minutes, 1)
        XCTAssertEqual(secondsOnly?.seconds, 30)
        XCTAssertNil(DurationOptionList.parseClock("abc"))
    }
}
