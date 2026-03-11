import XCTest
@testable import FocusTimer

final class SuggestionRequestGateTests: XCTestCase {
    func testLatestRequestTokenWins() {
        var gate = SuggestionRequestGate<String>()
        let first = gate.beginRequest(for: "live")
        let second = gate.beginRequest(for: "live")

        XCTAssertFalse(gate.isCurrent(first, for: "live"))
        XCTAssertTrue(gate.isCurrent(second, for: "live"))
    }

    func testCompleteRequestClearsCurrentToken() {
        var gate = SuggestionRequestGate<String>()
        let token = gate.beginRequest(for: "subtask-1")
        XCTAssertTrue(gate.isCurrent(token, for: "subtask-1"))

        gate.completeRequest(token, for: "subtask-1")
        XCTAssertFalse(gate.isCurrent(token, for: "subtask-1"))
    }

    func testInvalidateMarksPreviousTokenAsStale() {
        var gate = SuggestionRequestGate<String>()
        let first = gate.beginRequest(for: "subtask-2")
        gate.invalidate("subtask-2")

        XCTAssertFalse(gate.isCurrent(first, for: "subtask-2"))
    }
}
