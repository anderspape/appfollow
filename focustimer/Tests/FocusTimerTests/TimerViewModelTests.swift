import XCTest
@testable import FocusTimer

@MainActor
final class TimerViewModelTests: XCTestCase {
    func testInitLoadsPersistedSettingsAndRequestsNotificationAuthorization() {
        let initial = FocusSettings(
            focusMinutes: 30,
            breakMinutes: 7,
            sessionTitle: "Inbox admin",
            sessionEmoji: "📥",
            sessionAccentHex: "#6A66DA",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, notifications) = makeTimerViewModelForTests(initialSettings: initial)
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        XCTAssertEqual(viewModel.sessionTitle, initial.sessionTitle)
        XCTAssertEqual(viewModel.sessionEmoji, initial.sessionEmoji)
        XCTAssertEqual(viewModel.sessionAccentHex, initial.sessionAccentHex)
        XCTAssertEqual(viewModel.focusMinutes, Double(initial.focusMinutes))
        XCTAssertEqual(viewModel.breakMinutes, Double(initial.breakMinutes))
        XCTAssertEqual(viewModel.secondsRemaining, initial.focusMinutes * 60)
        XCTAssertEqual(viewModel.focusMusicEnabled, initial.focusMusicEnabled)
        XCTAssertEqual(viewModel.focusMusicProvider, initial.focusMusicProvider)
        XCTAssertEqual(viewModel.spotifyPlaylistURIOrURL, initial.spotifyPlaylistURIOrURL)
        XCTAssertEqual(notifications.authorizationRequestCount, 1)
    }

    func testUpdateSessionValuesAreNormalizedAndPersisted() {
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.updateSessionTitle("   ")
        viewModel.updateSessionEmoji("not-emoji")
        viewModel.updateSessionAccentHex("abc")

        XCTAssertEqual(viewModel.sessionTitle, FocusSettings.default.sessionTitle)
        XCTAssertEqual(viewModel.sessionEmoji, FocusSettings.default.sessionEmoji)
        XCTAssertEqual(viewModel.sessionAccentHex, "#AABBCC")

        let persisted = store.load()
        XCTAssertEqual(persisted.sessionTitle, FocusSettings.default.sessionTitle)
        XCTAssertEqual(persisted.sessionEmoji, FocusSettings.default.sessionEmoji)
        XCTAssertEqual(persisted.sessionAccentHex, "#AABBCC")
    }

    func testUpdateFocusMinutesClampsAndResyncsTimerWhenStopped() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.updateFocusMinutes(999)
        XCTAssertEqual(viewModel.focusMinutes, 180)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 180 * 60)
        XCTAssertEqual(viewModel.secondsRemaining, 180 * 60)

        viewModel.updateFocusMinutes(0)
        XCTAssertEqual(viewModel.focusMinutes, 1)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 60)
        XCTAssertEqual(viewModel.secondsRemaining, 60)
    }

    func testSubtaskTimersDriveFocusDurationFromTaskTotal() {
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([
            FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false),
            FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#ECEBFC", isDone: false)
        ])

        XCTAssertEqual(viewModel.focusMinutes, 20)
        XCTAssertEqual(viewModel.secondsRemaining, 8 * 60)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 8 * 60)
        XCTAssertEqual(viewModel.timerDisplayTitle, "Sort")
        XCTAssertTrue(viewModel.subTaskTimersEnabled)

        let persisted = store.load()
        XCTAssertEqual(persisted.focusMinutes, 20)
        XCTAssertEqual(persisted.subTasks.count, 2)
        XCTAssertTrue(persisted.subTaskTimersEnabled)
    }

    func testCompletingActiveSubtaskPromotesNextSubtaskAsTimerSource() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let firstTask = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        let secondTask = FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#A9D1D6", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([firstTask, secondTask])

        XCTAssertEqual(viewModel.timerDisplayTitle, "Sort")
        XCTAssertEqual(viewModel.timerDisplayEmoji, "🧺")
        XCTAssertEqual(viewModel.secondsRemaining, 8 * 60)

        viewModel.toggleTask(id: firstTask.id)

        XCTAssertEqual(viewModel.timerDisplayTitle, "Wash")
        XCTAssertEqual(viewModel.timerDisplayEmoji, "🧼")
        XCTAssertEqual(viewModel.secondsRemaining, 12 * 60)
        XCTAssertEqual(viewModel.tasks.last?.id, firstTask.id)
    }

    func testCompletingTaskEmitsCompletionEvent() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let task = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([task])

        let initialEventCount = viewModel.completedTaskEventCounter
        viewModel.toggleTask(id: task.id)

        XCTAssertEqual(viewModel.completedTaskEventCounter, initialEventCount + 1)

        viewModel.toggleTask(id: task.id)
        XCTAssertEqual(viewModel.completedTaskEventCounter, initialEventCount + 1)
    }

    func testUncompletingTaskReturnsToPreviousPosition() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let first = FocusTask(emoji: "1️⃣", title: "First", durationMinutes: 5, accentHex: "#ECEBFC", isDone: false)
        let second = FocusTask(emoji: "2️⃣", title: "Second", durationMinutes: 5, accentHex: "#A9D1D6", isDone: false)
        let third = FocusTask(emoji: "3️⃣", title: "Third", durationMinutes: 5, accentHex: "#CEE281", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([first, second, third])

        viewModel.toggleTask(id: second.id)
        XCTAssertEqual(viewModel.tasks.map(\.id), [first.id, third.id, second.id])

        viewModel.toggleTask(id: second.id)
        XCTAssertEqual(viewModel.tasks.map(\.id), [first.id, second.id, third.id])
        XCTAssertTrue(viewModel.tasks.allSatisfy { !$0.isDone })
    }

    func testCompletingLastSubtaskEntersResetState() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let first = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        let second = FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#A9D1D6", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([first, second])

        viewModel.toggleTask(id: first.id)
        viewModel.toggleTask(id: second.id)

        XCTAssertTrue(viewModel.shouldShowResetCTA)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.secondsRemaining, 20 * 60)
        XCTAssertTrue(viewModel.tasks.allSatisfy(\.isDone))
    }

    func testResetCompletedSubtasksAndStartUnchecksAndStartsFirstTask() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let first = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        let second = FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#A9D1D6", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([first, second])

        viewModel.toggleTask(id: first.id)
        viewModel.toggleTask(id: second.id)
        XCTAssertTrue(viewModel.shouldShowResetCTA)

        viewModel.resetCompletedSubtasksAndStart()

        XCTAssertFalse(viewModel.shouldShowResetCTA)
        XCTAssertTrue(viewModel.isRunning)
        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.timerDisplayTitle, "Sort")
        XCTAssertEqual(viewModel.secondsRemaining, 8 * 60)
        XCTAssertTrue(viewModel.tasks.allSatisfy { !$0.isDone })
    }

    func testCompletingLastSubtaskWithoutSubtaskTimersEntersResetState() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.updateFocusMinutes(30)
        viewModel.updateSubTaskTimersEnabled(false)

        let first = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        let second = FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#A9D1D6", isDone: false)
        viewModel.updateTasks([first, second])

        viewModel.toggleTask(id: first.id)
        viewModel.toggleTask(id: second.id)

        XCTAssertTrue(viewModel.shouldShowResetCTA)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.phase, .focus)
        XCTAssertEqual(viewModel.secondsRemaining, 30 * 60)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 30 * 60)
        XCTAssertTrue(viewModel.tasks.allSatisfy(\.isDone))
    }

    func testApplyTaskTemplateUpdatesDisplayAndDuration() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let template = TaskTemplate(
            title: "Laundry routine",
            emoji: "🧺",
            accentHex: "#A9D1D6",
            focusMinutes: 40,
            subTasks: [
                FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 10, accentHex: "#A9D1D6", isDone: false),
                FocusTask(emoji: "🫧", title: "Wash", durationMinutes: 15, accentHex: "#CEE281", isDone: false)
            ],
            subTaskTimersEnabled: true
        )

        viewModel.applyTaskTemplate(template, startImmediately: false)

        XCTAssertEqual(viewModel.sessionTitle, "Laundry routine")
        XCTAssertEqual(viewModel.timerDisplayTitle, "Sort")
        XCTAssertEqual(viewModel.timerDisplayEmoji, "🧺")
        XCTAssertEqual(viewModel.timerDisplayAccentHex, "#A9D1D6")
        XCTAssertEqual(viewModel.secondsRemaining, 10 * 60)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 10 * 60)
        XCTAssertFalse(viewModel.isRunning)
    }

    func testCurrentTaskTemplateStripsCompletedStateFromSubtasks() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([
            FocusTask(emoji: "✅", title: "Done", durationMinutes: 5, accentHex: "#ECEBFC", isDone: true),
            FocusTask(emoji: "🧺", title: "Next", durationMinutes: 15, accentHex: "#A9D1D6", isDone: false)
        ])

        let template = viewModel.currentTaskTemplate()
        XCTAssertEqual(template.subTasks.count, 2)
        XCTAssertTrue(template.subTasks.allSatisfy { !$0.isDone })
    }

    func testCurrentTaskTemplatePreservesCanonicalOrderWhenTaskIsCompleted() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let first = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        let second = FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#A9D1D6", isDone: false)
        let third = FocusTask(emoji: "🧹", title: "Fold", durationMinutes: 5, accentHex: "#CEE281", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([first, second, third])

        viewModel.toggleTask(id: second.id)
        XCTAssertEqual(viewModel.tasks.map(\.id), [first.id, third.id, second.id])

        let template = viewModel.currentTaskTemplate()
        XCTAssertEqual(template.subTasks.map(\.id), [first.id, second.id, third.id])
        XCTAssertTrue(template.subTasks.allSatisfy { !$0.isDone })
    }

    func testCurrentTaskTemplateFavoriteSignatureIsStableAcrossCompletionToggles() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let first = FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 8, accentHex: "#ECEBFC", isDone: false)
        let second = FocusTask(emoji: "🧼", title: "Wash", durationMinutes: 12, accentHex: "#A9D1D6", isDone: false)
        let third = FocusTask(emoji: "🧹", title: "Fold", durationMinutes: 5, accentHex: "#CEE281", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([first, second, third])

        let baselineSignature = viewModel.currentTaskTemplate().favoriteSignature

        viewModel.toggleTask(id: second.id)
        let completedSignature = viewModel.currentTaskTemplate().favoriteSignature
        XCTAssertEqual(completedSignature, baselineSignature)

        viewModel.toggleTask(id: second.id)
        let reopenedSignature = viewModel.currentTaskTemplate().favoriteSignature
        XCTAssertEqual(reopenedSignature, baselineSignature)
    }

    func testUpdateTasksNormalizesDuplicateIDsAndInvalidValues() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let sharedID = UUID()
        viewModel.updateTasks([
            FocusTask(id: sharedID, emoji: "not-emoji", title: "   ", durationMinutes: 0, accentHex: "oops", isDone: false),
            FocusTask(id: sharedID, emoji: "✅", title: "Keep", durationMinutes: 999, accentHex: "#123123", isDone: true)
        ])

        XCTAssertEqual(viewModel.tasks.count, 2)
        XCTAssertEqual(Set(viewModel.tasks.map(\.id)).count, 2)
        XCTAssertTrue(viewModel.tasks.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertTrue(viewModel.tasks.allSatisfy { (1...120).contains($0.durationMinutes) })
        XCTAssertEqual(viewModel.tasks[0].emoji, FocusTask.defaultEmoji)
    }

    func testResumingTimerKeepsRemainingTimeForActiveSubtask() {
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let task = FocusTask(emoji: "🏃‍♂️", title: "Run", durationMinutes: 20, accentHex: "#A9D1D6", isDone: false)
        viewModel.updateSubTaskTimersEnabled(true)
        viewModel.updateTasks([task])
        viewModel.secondsRemaining = 7 * 60

        viewModel.toggleTimer() // start / resume

        XCTAssertEqual(viewModel.secondsRemaining, 7 * 60)
        XCTAssertEqual(viewModel.phaseDurationSeconds, 20 * 60)
        XCTAssertTrue(viewModel.isRunning)
    }

    func testStartingTimerWithFocusMusicEnabledTriggersPlayback() async {
        let focusMusicController = MockFocusMusicController()
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.toggleTimer()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(focusMusicController.playInvocations.count, 1)
        XCTAssertEqual(focusMusicController.playInvocations.first!, initial.spotifyPlaylistURIOrURL)
    }

    func testStartingTimerWithFocusMusicDisabledDoesNotTriggerPlayback() async {
        let focusMusicController = MockFocusMusicController()
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: false,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.toggleTimer()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertTrue(focusMusicController.playInvocations.isEmpty)
    }

    func testManualMusicControlsForwardToController() async {
        let focusMusicController = MockFocusMusicController()
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.playFocusMusicManually()
        viewModel.pauseFocusMusicManually()
        viewModel.nextFocusMusicTrack()
        viewModel.previousFocusMusicTrack()
        viewModel.seekFocusMusicBackward(seconds: 10)
        viewModel.seekFocusMusicForward(seconds: 15)
        viewModel.decreaseFocusMusicVolume(step: 7)
        viewModel.increaseFocusMusicVolume(step: 9)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(focusMusicController.playInvocations.count, 1)
        XCTAssertEqual(focusMusicController.pauseInvocationCount, 1)
        XCTAssertEqual(focusMusicController.nextInvocationCount, 1)
        XCTAssertEqual(focusMusicController.previousInvocationCount, 1)
        XCTAssertEqual(focusMusicController.seekInvocations.count, 2)
        XCTAssertEqual(Set(focusMusicController.seekInvocations), Set([-10, 15]))
        XCTAssertEqual(focusMusicController.adjustVolumeInvocations.count, 2)
        XCTAssertEqual(Set(focusMusicController.adjustVolumeInvocations), Set([-7, 9]))
    }

    func testUpdateSpotifyPlaylistRejectsInvalidValueAndKeepsPrevious() {
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let previous = viewModel.spotifyPlaylistURIOrURL
        let isValid = viewModel.updateSpotifyPlaylistURIOrURL("not-a-spotify-playlist")

        XCTAssertFalse(isValid)
        XCTAssertEqual(viewModel.spotifyPlaylistURIOrURL, previous)
        XCTAssertEqual(store.load().spotifyPlaylistURIOrURL, previous)
    }

    func testEmptySpotifyPlaylistUsesDefaultPlaylist() {
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            spotifyPlaylistURIOrURL: ""
        )
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests(initialSettings: initial)
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        XCTAssertEqual(viewModel.spotifyPlaylistURIOrURL, FocusSettings.default.spotifyPlaylistURIOrURL)

        let accepted = viewModel.updateSpotifyPlaylistURIOrURL("   ")
        XCTAssertTrue(accepted)
        XCTAssertEqual(viewModel.spotifyPlaylistURIOrURL, FocusSettings.default.spotifyPlaylistURIOrURL)
        XCTAssertEqual(store.load().spotifyPlaylistURIOrURL, FocusSettings.default.spotifyPlaylistURIOrURL)
    }

    func testPlaybackSnapshotUpdatesDisplayedTrackAndPlayPauseState() async {
        let focusMusicController = MockFocusMusicController()
        focusMusicController.playbackSnapshotResult = FocusMusicPlaybackSnapshot(
            isPlaying: true,
            isMuted: false,
            trackTitle: "Midnight City",
            artistName: "M83",
            albumTitle: "Hurry Up, We're Dreaming",
            artworkURL: URL(string: "https://i.scdn.co/image/current-track"),
            playbackPositionSeconds: 141,
            trackDurationSeconds: 210
        )
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertTrue(viewModel.isFocusMusicPlaying)
        XCTAssertEqual(viewModel.spotifyPlaybackContextLabel, "Nu spiller")
        XCTAssertEqual(viewModel.spotifyPlaybackPrimaryLabel, "Midnight City")
        XCTAssertEqual(viewModel.spotifyPlaybackSecondaryLabel, "M83 / Hurry Up, We're Dreaming")
        XCTAssertEqual(viewModel.spotifyPlaybackCoverURL?.absoluteString, "https://i.scdn.co/image/current-track")
        XCTAssertEqual(viewModel.spotifyPlaybackElapsedLabel, "2:21")
        XCTAssertEqual(viewModel.spotifyPlaybackDurationLabel, "3:30")
        XCTAssertGreaterThanOrEqual(focusMusicController.playbackSnapshotInvocationCount, 1)
    }

    func testPausedSpotifyTrackStillShowsArtistAndAlbum() async {
        let focusMusicController = MockFocusMusicController()
        focusMusicController.playbackSnapshotResult = FocusMusicPlaybackSnapshot(
            isPlaying: false,
            isMuted: false,
            trackTitle: "Where I Belong",
            artistName: "Joey Bada$$",
            albumTitle: "Where I Belong",
            artworkURL: URL(string: "https://i.scdn.co/image/paused-track"),
            playbackPositionSeconds: 5,
            trackDurationSeconds: 180
        )
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertFalse(viewModel.isFocusMusicPlaying)
        XCTAssertEqual(viewModel.spotifyPlaybackPrimaryLabel, "Where I Belong")
        XCTAssertEqual(viewModel.spotifyPlaybackSecondaryLabel, "Joey Bada$$ / Where I Belong")
    }

    func testMetadataFetchOnInitUpdatesPlaylistMetadata() async {
        let provider = MockSpotifyPlaylistMetadataProvider()
        await provider.setResult(
            .success(
                SpotifyPlaylistMetadata(
                    title: "Deep Focus",
                    typeLabel: "Offentlig playliste",
                    thumbnailURL: URL(string: "https://i.scdn.co/image/test"),
                    sourceURL: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6")!
                )
            )
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            spotifyMetadataProvider: provider
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        try? await Task.sleep(nanoseconds: 40_000_000)
        let invocationCount = await provider.invocationCount()
        XCTAssertEqual(viewModel.spotifyPlaylistMetadata?.title, "Deep Focus")
        XCTAssertEqual(viewModel.spotifyPlaylistCategoryLabel, "Offentlig playliste")
        XCTAssertEqual(invocationCount, 1)
    }

    func testMetadataRefreshForcedAfterPlaylistUpdate() async {
        let provider = MockSpotifyPlaylistMetadataProvider()
        await provider.setResult(
            .success(
                SpotifyPlaylistMetadata(
                    title: "Flow State",
                    typeLabel: "Offentlig playliste",
                    thumbnailURL: nil,
                    sourceURL: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6")!
                )
            )
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            spotifyMetadataProvider: provider
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        _ = viewModel.updateSpotifyPlaylistURIOrURL("spotify:playlist:37i9dQZF1DWZd79rJ6a7lp")
        try? await Task.sleep(nanoseconds: 40_000_000)
        let invocationCount = await provider.invocationCount()

        XCTAssertEqual(viewModel.spotifyPlaylistMetadata?.title, "Flow State")
        XCTAssertGreaterThanOrEqual(invocationCount, 2)
    }

    func testPlaylistSaveUpdatesPlayerCardMetadataWhenSpotifyIsPaused() async {
        let provider = MockSpotifyPlaylistMetadataProvider()
        await provider.setResult(
            .success(
                SpotifyPlaylistMetadata(
                    title: "Old Playlist",
                    typeLabel: "Offentlig playliste",
                    thumbnailURL: URL(string: "https://i.scdn.co/image/old"),
                    sourceURL: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6")!
                )
            )
        )

        let focusMusicController = MockFocusMusicController()
        focusMusicController.playbackSnapshotResult = FocusMusicPlaybackSnapshot(
            isPlaying: false,
            isMuted: false,
            trackTitle: nil,
            artistName: nil,
            albumTitle: nil,
            artworkURL: nil,
            playbackPositionSeconds: nil,
            trackDurationSeconds: nil
        )

        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )

        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController,
            spotifyMetadataProvider: provider
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        try? await Task.sleep(nanoseconds: 90_000_000)

        await provider.setResult(
            .success(
                SpotifyPlaylistMetadata(
                    title: "Fresh Playlist",
                    typeLabel: "Offentlig playliste",
                    thumbnailURL: URL(string: "https://i.scdn.co/image/new"),
                    sourceURL: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DWZd79rJ6a7lp")!
                )
            )
        )

        _ = viewModel.updateSpotifyPlaylistURIOrURL("spotify:playlist:37i9dQZF1DWZd79rJ6a7lp")
        try? await Task.sleep(nanoseconds: 90_000_000)

        XCTAssertFalse(viewModel.isFocusMusicPlaying)
        XCTAssertEqual(viewModel.spotifyPlaybackPrimaryLabel, "Fresh Playlist")
        XCTAssertEqual(viewModel.spotifyPlaybackSecondaryLabel, "")
        XCTAssertEqual(viewModel.spotifyPlaybackCoverURL?.absoluteString, "https://i.scdn.co/image/new")
        XCTAssertEqual(viewModel.spotifyPlaybackElapsedLabel, "--:--")
        XCTAssertEqual(viewModel.spotifyPlaybackDurationLabel, "--:--")
    }

    func testSyncSpotifyPreviewToSavedPlaylistRunsPlayPauseWhenPaused() async {
        let focusMusicController = MockFocusMusicController()
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.syncSpotifyPreviewToSavedPlaylistIfNeeded()
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertEqual(focusMusicController.playInvocations.count, 1)
        XCTAssertEqual(focusMusicController.playInvocations.first ?? nil, "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6")
        XCTAssertEqual(focusMusicController.pauseInvocationCount, 1)
        XCTAssertFalse(viewModel.isFocusMusicPlaying)
    }

    func testMetadataFailureDoesNotAffectMusicPlaybackFlow() async {
        let provider = MockSpotifyPlaylistMetadataProvider()
        await provider.setResult(.networkError)
        let focusMusicController = MockFocusMusicController()
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController,
            spotifyMetadataProvider: provider
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.toggleTimer()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(viewModel.spotifyPlaylistMetadataStatus, .networkError)
        XCTAssertEqual(focusMusicController.playInvocations.count, 1)
    }

    func testMuteDoesNotDisableSpotifyFeature() async {
        let focusMusicController = MockFocusMusicController()
        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true,
            focusMusicProvider: .spotify,
            spotifyPlaylistURIOrURL: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6",
            aiEnabled: true
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: focusMusicController
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.toggleFocusMusicMuted()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertTrue(viewModel.focusMusicEnabled)
        XCTAssertTrue(viewModel.isFocusMusicMuted)
        XCTAssertEqual(focusMusicController.setMutedInvocations, [true])
    }

    func testAutoFallbackSetsFallbackStateWhenSpotifyMissing() async {
        let hybrid = MockHybridFocusMusicController()
        hybrid.activatesFallbackOnPlay = true
        hybrid.fallbackChannels = [
            TiimoMusicChannel(
                id: "https://cdn.example.com/lofi.m4a",
                name: "Lo-Fi",
                colorHex: "#D9CEFF",
                fileURL: URL(string: "https://cdn.example.com/lofi.m4a")!,
                coverURL: URL(string: "https://cdn.example.com/lofi.png")
            )
        ]

        let initial = FocusSettings(
            focusMinutes: 25,
            breakMinutes: 5,
            sessionTitle: "Focus",
            sessionEmoji: "🌱",
            sessionAccentHex: "#9E84FF",
            subTasks: [],
            subTaskTimersEnabled: false,
            focusMusicEnabled: true
        )
        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: initial,
            focusMusicController: hybrid
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.toggleTimer()
        try? await Task.sleep(nanoseconds: 70_000_000)

        XCTAssertTrue(viewModel.isFallbackMusicActive)
        XCTAssertEqual(viewModel.fallbackChannels.first?.name, "Lo-Fi")
    }

    func testDefaultFallbackChannelPersistsToSettings() {
        let hybrid = MockHybridFocusMusicController()
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests(
            focusMusicController: hybrid
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.updateDefaultFallbackChannelID("https://cdn.example.com/lofi.m4a")

        XCTAssertEqual(viewModel.defaultFallbackChannelID, "https://cdn.example.com/lofi.m4a")
        XCTAssertEqual(hybrid.defaultFallbackMusicChannelID, "https://cdn.example.com/lofi.m4a")
        XCTAssertEqual(store.load().defaultFallbackMusicChannelID, "https://cdn.example.com/lofi.m4a")
    }

    func testSwitchBackActionDelegatesToHybridController() async {
        let hybrid = MockHybridFocusMusicController()
        hybrid.isUsingFallbackMusic = true
        hybrid.canSwitchBackToSpotifyNow = true

        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            focusMusicController: hybrid
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        viewModel.switchBackToSpotifyFromFallback()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(hybrid.switchBackInvocationCount, 1)
        XCTAssertFalse(viewModel.isFallbackMusicActive)
    }

    func testTiimoProviderUsesLofiChannelMetadataWhenNoNowPlayingSnapshot() {
        let lofiURL = URL(string: "https://cdn.example.com/lofi-cover.jpg")!
        let acousticURL = URL(string: "https://cdn.example.com/acoustic-cover.jpg")!
        let hybrid = MockHybridFocusMusicController()
        hybrid.fallbackChannels = [
            TiimoMusicChannel(
                id: "acoustic",
                name: "Acoustic Chill",
                colorHex: nil,
                fileURL: URL(string: "https://cdn.example.com/acoustic.m3u8")!,
                coverURL: acousticURL
            ),
            TiimoMusicChannel(
                id: "lofi",
                name: "Lo-Fi Focus",
                colorHex: nil,
                fileURL: URL(string: "https://cdn.example.com/lofi.m3u8")!,
                coverURL: lofiURL
            )
        ]

        let tiimoSettings = FocusSettings(
            focusMinutes: FocusSettings.default.focusMinutes,
            breakMinutes: FocusSettings.default.breakMinutes,
            sessionTitle: FocusSettings.default.sessionTitle,
            sessionEmoji: FocusSettings.default.sessionEmoji,
            sessionAccentHex: FocusSettings.default.sessionAccentHex,
            subTasks: FocusSettings.default.subTasks,
            subTaskTimersEnabled: FocusSettings.default.subTaskTimersEnabled,
            focusMusicEnabled: true,
            focusMusicProvider: .tiimoRadio,
            spotifyPlaylistURIOrURL: FocusSettings.default.spotifyPlaylistURIOrURL,
            defaultFallbackMusicChannelID: nil,
            aiEnabled: FocusSettings.default.aiEnabled
        )

        let (viewModel, _, defaults, suiteName, _) = makeTimerViewModelForTests(
            initialSettings: tiimoSettings,
            focusMusicController: hybrid
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        XCTAssertEqual(viewModel.activeFocusMusicProvider, .tiimoRadio)
        XCTAssertEqual(viewModel.spotifyPlaybackPrimaryLabel, "Lo-Fi Focus")
        XCTAssertEqual(viewModel.spotifyPlaybackSecondaryLabel, "Tiimo Radio")
        XCTAssertEqual(viewModel.spotifyPlaybackCoverURL, lofiURL)
        XCTAssertEqual(viewModel.defaultFallbackChannelID, "lofi")
    }

    func testUpdateFocusMusicProviderSwitchesBetweenSpotifyAndTiimoRadio() {
        let hybrid = MockHybridFocusMusicController()
        let (viewModel, store, defaults, suiteName, _) = makeTimerViewModelForTests(
            focusMusicController: hybrid
        )
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        XCTAssertEqual(viewModel.focusMusicProvider, .spotify)
        XCTAssertEqual(viewModel.activeFocusMusicProvider, .spotify)

        viewModel.updateFocusMusicProvider(.tiimoRadio)

        XCTAssertEqual(viewModel.focusMusicProvider, .tiimoRadio)
        XCTAssertEqual(viewModel.activeFocusMusicProvider, .tiimoRadio)
        XCTAssertEqual(hybrid.preferredProvider, .tiimoRadio)
        XCTAssertEqual(store.load().focusMusicProvider, .tiimoRadio)
    }
}
