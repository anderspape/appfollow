import XCTest
@testable import FocusTimer

@MainActor
final class SettingsSyncIntegrationTests: XCTestCase {
    func testExternalSettingsChangeUpdatesViewModelState() async {
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let synced = FocusSettings(
            focusMinutes: 99, // should be overridden by sub-task total when sub-task timers are enabled
            breakMinutes: 12,
            sessionTitle: "Yoga",
            sessionEmoji: "🧘",
            sessionAccentHex: "#CEE281",
            subTasks: [
                FocusTask(emoji: "🧘", title: "Breath", durationMinutes: 10, accentHex: "#ECEBFC", isDone: false),
                FocusTask(emoji: "🧘", title: "Stretch", durationMinutes: 15, accentHex: "#ECEBFC", isDone: false)
            ],
            subTaskTimersEnabled: true
        )

        store.onExternalSettingsChange?(synced)
        await flushMainActor()

        XCTAssertEqual(viewModel.sessionTitle, "Yoga")
        XCTAssertEqual(viewModel.sessionEmoji, "🧘")
        XCTAssertEqual(viewModel.sessionAccentHex, "#CEE281")
        XCTAssertEqual(viewModel.breakMinutes, 12)
        XCTAssertEqual(viewModel.focusMinutes, 25)
        XCTAssertEqual(viewModel.secondsRemaining, 10 * 60)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 10 * 60)
        XCTAssertTrue(viewModel.subTaskTimersEnabled)
        XCTAssertEqual(viewModel.tasks.count, 2)
    }

    func testViewModelPersistsAgainAfterExternalSync() async {
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let synced = FocusSettings(
            focusMinutes: 20,
            breakMinutes: 5,
            sessionTitle: "Synced",
            sessionEmoji: "✅",
            sessionAccentHex: "#ECEBFC",
            subTasks: [FocusTask(emoji: "✅", title: "Check", durationMinutes: 20, accentHex: "#ECEBFC", isDone: false)],
            subTaskTimersEnabled: true
        )

        store.onExternalSettingsChange?(synced)
        await flushMainActor()

        viewModel.updateSessionTitle("After sync edit")
        let persisted = store.load()

        XCTAssertEqual(persisted.sessionTitle, "After sync edit")
        XCTAssertEqual(persisted.focusMinutes, 20)
        XCTAssertEqual(persisted.subTasks.count, 1)
        XCTAssertTrue(persisted.subTaskTimersEnabled)
    }

    private func flushMainActor() async {
        await Task.yield()
        await Task.yield()
    }
}
