import XCTest
@testable import FocusTimer

@MainActor
final class StatusBarNavigationBridgeTests: XCTestCase {
    func testSendUpdatesCommandAndVersion() {
        let bridge = StatusBarNavigationBridge()
        XCTAssertEqual(bridge.commandVersion, 0)
        XCTAssertEqual(bridge.latestCommand, .openTimer)

        bridge.send(.openSettings)
        XCTAssertEqual(bridge.latestCommand, .openSettings)
        XCTAssertEqual(bridge.commandVersion, 1)

        bridge.send(.openSettings)
        XCTAssertEqual(bridge.latestCommand, .openSettings)
        XCTAssertEqual(bridge.commandVersion, 2)

        bridge.send(.openTimer)
        XCTAssertEqual(bridge.latestCommand, .openTimer)
        XCTAssertEqual(bridge.commandVersion, 3)
    }
}
