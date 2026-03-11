import XCTest
@testable import FocusTimer

final class StatusBarPanelHeightPolicyTests: XCTestCase {
    func testTimerMinifiedUsesMinimumPanelHeightFloor() {
        let result = StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: 8,
            panelOuterPadding: 0,
            contentVerticalPadding: 0,
            context: .timerMinified
        )

        XCTAssertEqual(result, StatusBarLayout.minimumPanelHeight, accuracy: 0.001)
    }

    func testTimerMinifiedExpandsWithContentAndPadding() {
        let result = StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: 100,
            panelOuterPadding: 14,
            contentVerticalPadding: 28,
            context: .timerMinified
        )

        XCTAssertEqual(result, 128, accuracy: 0.001)
    }

    func testTimerFullWithMusicReservesExpandedHeight() {
        let result = StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: 300,
            panelOuterPadding: 14,
            contentVerticalPadding: 28,
            context: .timerFull(focusMusicEnabled: true)
        )

        XCTAssertEqual(result, StatusBarLayout.timerFullHeightWhenMusicExpanded, accuracy: 0.001)
    }

    func testTimerFullWithoutMusicReservesDefaultFullHeight() {
        let result = StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: 300,
            panelOuterPadding: 14,
            contentVerticalPadding: 28,
            context: .timerFull(focusMusicEnabled: false)
        )

        XCTAssertEqual(result, StatusBarLayout.timerFullHeightWithoutMusic, accuracy: 0.001)
    }

    func testTimerFullCanGrowBeyondReservedHeight() {
        let result = StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: 950,
            panelOuterPadding: 14,
            contentVerticalPadding: 28,
            context: .timerFull(focusMusicEnabled: true)
        )

        XCTAssertEqual(result, 978, accuracy: 0.001)
    }

    func testNonTimerScreenUsesMinimumContentFloor() {
        let result = StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: 90,
            panelOuterPadding: 14,
            contentVerticalPadding: 28,
            context: .nonTimer
        )

        XCTAssertEqual(
            result,
            StatusBarLayout.screenMinimumContentHeight + 28,
            accuracy: 0.001
        )
    }
}
