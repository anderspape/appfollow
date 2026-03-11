import XCTest
@testable import FocusTimer

final class TaskTemplateTests: XCTestCase {
    func testFavoriteSignatureIgnoresSubtaskCompletionState() {
        let baseTasks = [
            FocusTask(emoji: "✅", title: "Step one", durationMinutes: 5, accentHex: "#ECEBFC", isDone: false),
            FocusTask(emoji: "🧺", title: "Step two", durationMinutes: 10, accentHex: "#A9D1D6", isDone: false)
        ]
        var completedTasks = baseTasks
        completedTasks[0].isDone = true

        let original = TaskTemplate(
            title: "Run 10k",
            emoji: "🏃‍♂️",
            accentHex: "#A9D1D6",
            focusMinutes: 15,
            subTasks: baseTasks,
            subTaskTimersEnabled: true
        )
        let completed = TaskTemplate(
            title: "Run 10k",
            emoji: "🏃‍♂️",
            accentHex: "#A9D1D6",
            focusMinutes: 15,
            subTasks: completedTasks,
            subTaskTimersEnabled: true
        )

        XCTAssertEqual(original.favoriteSignature, completed.favoriteSignature)
    }

    func testFavoriteSignatureNormalizesCaseAndWhitespace() {
        let left = TaskTemplate(
            title: "  Run 10k  ",
            emoji: "🏃‍♂️",
            accentHex: "a9d1d6",
            focusMinutes: 30,
            subTasks: [
                FocusTask(emoji: "✅", title: " Step One ", durationMinutes: 5, accentHex: "ecebfc", isDone: false)
            ],
            subTaskTimersEnabled: true
        )
        let right = TaskTemplate(
            title: "run 10k",
            emoji: "🏃‍♂️",
            accentHex: "#A9D1D6",
            focusMinutes: 30,
            subTasks: [
                FocusTask(emoji: "✅", title: "step one", durationMinutes: 5, accentHex: "#ECEBFC", isDone: false)
            ],
            subTaskTimersEnabled: true
        )

        XCTAssertEqual(left.favoriteSignature, right.favoriteSignature)
    }

    func testFavoriteSignatureChangesWhenDurationChanges() {
        let short = TaskTemplate(
            title: "Run 10k",
            emoji: "🏃‍♂️",
            accentHex: "#A9D1D6",
            focusMinutes: 20,
            subTasks: [
                FocusTask(emoji: "✅", title: "Warm up", durationMinutes: 5, accentHex: "#ECEBFC", isDone: false),
                FocusTask(emoji: "🏃‍♂️", title: "Intervals", durationMinutes: 15, accentHex: "#A9D1D6", isDone: false)
            ],
            subTaskTimersEnabled: true
        )
        let long = TaskTemplate(
            title: "Run 10k",
            emoji: "🏃‍♂️",
            accentHex: "#A9D1D6",
            focusMinutes: 25,
            subTasks: [
                FocusTask(emoji: "✅", title: "Warm up", durationMinutes: 5, accentHex: "#ECEBFC", isDone: false),
                FocusTask(emoji: "🏃‍♂️", title: "Intervals", durationMinutes: 20, accentHex: "#A9D1D6", isDone: false)
            ],
            subTaskTimersEnabled: true
        )

        XCTAssertNotEqual(short.favoriteSignature, long.favoriteSignature)
    }
}
