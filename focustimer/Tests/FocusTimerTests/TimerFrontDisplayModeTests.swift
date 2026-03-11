import XCTest
@testable import FocusTimer

final class TimerFrontDisplayModeTests: XCTestCase {
    func testUnknownStoredValueFallsBackToFull() {
        XCTAssertEqual(TimerFrontDisplayMode.fromStoredValue(nil), .full)
        XCTAssertEqual(TimerFrontDisplayMode.fromStoredValue(""), .full)
        XCTAssertEqual(TimerFrontDisplayMode.fromStoredValue("compact"), .full)
    }

    func testStoredValueRoundTrip() {
        for mode in TimerFrontDisplayMode.allCases {
            XCTAssertEqual(TimerFrontDisplayMode.fromStoredValue(mode.rawValue), mode)
        }
    }
}
