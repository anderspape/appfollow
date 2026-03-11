import Foundation
@testable import FocusTimer

enum TestSettingsFactory {
    static let storageKey = "focus_timer.settings.v1"

    static func makeDefaultsSuite() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "FocusTimerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite: \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    static func tearDownSuite(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    static func makeSettingsStore(seed settings: FocusSettings? = nil) -> (store: SettingsStore, defaults: UserDefaults, suiteName: String) {
        let (defaults, suiteName) = makeDefaultsSuite()
        let store = SettingsStore(defaults: defaults, cloudSync: nil)
        if let settings {
            store.save(settings)
        }
        return (store, defaults, suiteName)
    }
}

final class MockNotificationService: NotificationServicing {
    private(set) var authorizationRequestCount = 0
    private(set) var phaseChanges: [(phase: SessionPhase, minutes: Int)] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequestCount += 1
    }

    func notifyPhaseChange(phase: SessionPhase, minutes: Int) {
        phaseChanges.append((phase: phase, minutes: minutes))
    }
}

struct NoopSessionSetupSuggester: SessionSetupSuggesting {
    func suggest(from prompt: String, current: SessionSetupSuggestion) async -> SessionSetupSuggestion? {
        nil
    }
}

struct NoopSubtaskBreakdownSuggester: SubtaskBreakdownSuggesting {
    func suggestSubtasks(title: String, totalMinutes: Int, current: [FocusTask]) async -> [FocusTask]? {
        nil
    }
}

actor NoopSpotifyPlaylistMetadataProvider: SpotifyPlaylistMetadataProviding {
    func fetchMetadata(for playlistInput: String) async -> SpotifyPlaylistMetadataResult {
        .networkError
    }
}

actor MockSpotifyPlaylistMetadataProvider: SpotifyPlaylistMetadataProviding {
    private(set) var invocations: [String] = []
    var result: SpotifyPlaylistMetadataResult = .networkError

    func setResult(_ value: SpotifyPlaylistMetadataResult) {
        result = value
    }

    func invocationCount() -> Int {
        invocations.count
    }

    func fetchMetadata(for playlistInput: String) async -> SpotifyPlaylistMetadataResult {
        invocations.append(playlistInput)
        return result
    }
}

final class MockFocusMusicController: FocusMusicControlling {
    private let lock = NSLock()
    private(set) var playInvocations: [String?] = []
    private(set) var pauseInvocationCount = 0
    private(set) var nextInvocationCount = 0
    private(set) var previousInvocationCount = 0
    private(set) var seekInvocations: [Int] = []
    private(set) var adjustVolumeInvocations: [Int] = []
    private(set) var setMutedInvocations: [Bool] = []
    private(set) var openInvocations: [String?] = []
    private(set) var playbackSnapshotInvocationCount = 0

    var playResult: FocusMusicControlResult = .success
    var pauseResult: FocusMusicControlResult = .success
    var nextResult: FocusMusicControlResult = .success
    var previousResult: FocusMusicControlResult = .success
    var seekResult: FocusMusicControlResult = .success
    var adjustVolumeResult: FocusMusicControlResult = .success
    var setMutedResult: FocusMusicControlResult = .success
    var openResult: FocusMusicControlResult = .success
    var playbackSnapshotResult: FocusMusicPlaybackSnapshot?

    func play(playlist: String?) async -> FocusMusicControlResult {
        lock.withLock {
            playInvocations.append(playlist)
        }
        return playResult
    }

    func pause() async -> FocusMusicControlResult {
        lock.withLock {
            pauseInvocationCount += 1
        }
        return pauseResult
    }

    func next() async -> FocusMusicControlResult {
        lock.withLock {
            nextInvocationCount += 1
        }
        return nextResult
    }

    func previous() async -> FocusMusicControlResult {
        lock.withLock {
            previousInvocationCount += 1
        }
        return previousResult
    }

    func seek(by seconds: Int) async -> FocusMusicControlResult {
        lock.withLock {
            seekInvocations.append(seconds)
        }
        return seekResult
    }

    func adjustVolume(by delta: Int) async -> FocusMusicControlResult {
        lock.withLock {
            adjustVolumeInvocations.append(delta)
        }
        return adjustVolumeResult
    }

    func setMuted(_ muted: Bool) async -> FocusMusicControlResult {
        lock.withLock {
            setMutedInvocations.append(muted)
        }
        return setMutedResult
    }

    func openInSpotify(playlist: String?) async -> FocusMusicControlResult {
        lock.withLock {
            openInvocations.append(playlist)
        }
        return openResult
    }

    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? {
        lock.withLock {
            playbackSnapshotInvocationCount += 1
        }
        return playbackSnapshotResult
    }
}

final class MockHybridFocusMusicController: FocusMusicControlling, HybridFocusMusicStateProviding {
    private(set) var playInvocations: [String?] = []
    private(set) var pauseInvocationCount = 0
    private(set) var nextInvocationCount = 0
    private(set) var previousInvocationCount = 0
    private(set) var seekInvocations: [Int] = []
    private(set) var adjustVolumeInvocations: [Int] = []
    private(set) var setMutedInvocations: [Bool] = []
    private(set) var openInvocations: [String?] = []
    private(set) var refreshFallbackChannelsInvocationCount = 0
    private(set) var switchBackInvocationCount = 0

    var playResult: FocusMusicControlResult = .success
    var pauseResult: FocusMusicControlResult = .success
    var nextResult: FocusMusicControlResult = .success
    var previousResult: FocusMusicControlResult = .success
    var seekResult: FocusMusicControlResult = .success
    var adjustVolumeResult: FocusMusicControlResult = .success
    var setMutedResult: FocusMusicControlResult = .success
    var openResult: FocusMusicControlResult = .success
    var playbackSnapshotResult: FocusMusicPlaybackSnapshot?

    var isUsingFallbackMusic = false
    var fallbackChannels: [TiimoMusicChannel] = []
    var defaultFallbackMusicChannelID: String?
    var canSwitchBackToSpotifyNow = false
    var preferredProvider: FocusMusicProvider = .spotify
    var activeProvider: FocusMusicProvider = .spotify
    var activatesFallbackOnPlay = false
    var switchBackResult = true

    func play(playlist: String?) async -> FocusMusicControlResult {
        playInvocations.append(playlist)
        if activatesFallbackOnPlay, playResult == .success {
            isUsingFallbackMusic = true
            activeProvider = .tiimoRadio
        }
        if preferredProvider == .tiimoRadio {
            isUsingFallbackMusic = true
            activeProvider = .tiimoRadio
        }
        return playResult
    }

    func pause() async -> FocusMusicControlResult {
        pauseInvocationCount += 1
        return pauseResult
    }

    func next() async -> FocusMusicControlResult {
        nextInvocationCount += 1
        return nextResult
    }

    func previous() async -> FocusMusicControlResult {
        previousInvocationCount += 1
        return previousResult
    }

    func seek(by seconds: Int) async -> FocusMusicControlResult {
        seekInvocations.append(seconds)
        return seekResult
    }

    func adjustVolume(by delta: Int) async -> FocusMusicControlResult {
        adjustVolumeInvocations.append(delta)
        return adjustVolumeResult
    }

    func setMuted(_ muted: Bool) async -> FocusMusicControlResult {
        setMutedInvocations.append(muted)
        return setMutedResult
    }

    func openInSpotify(playlist: String?) async -> FocusMusicControlResult {
        openInvocations.append(playlist)
        return openResult
    }

    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? {
        playbackSnapshotResult
    }

    func setDefaultFallbackMusicChannelID(_ id: String?) {
        defaultFallbackMusicChannelID = id
    }

    func setPreferredProvider(_ provider: FocusMusicProvider) {
        preferredProvider = provider
        if provider == .tiimoRadio {
            isUsingFallbackMusic = true
            activeProvider = .tiimoRadio
        } else {
            activeProvider = .spotify
        }
    }

    func pauseAllProvidersForSwitch() async {
        pauseInvocationCount += 1
    }

    func refreshFallbackChannels() async {
        refreshFallbackChannelsInvocationCount += 1
    }

    func switchBackToSpotifyIfAvailable() async -> Bool {
        switchBackInvocationCount += 1
        if switchBackResult {
            isUsingFallbackMusic = false
            canSwitchBackToSpotifyNow = false
            preferredProvider = .spotify
            activeProvider = .spotify
        }
        return switchBackResult
    }
}

@MainActor
func makeTimerViewModelForTests(
    initialSettings: FocusSettings = .default,
    focusMusicController: FocusMusicControlling = MockFocusMusicController(),
    spotifyMetadataProvider: SpotifyPlaylistMetadataProviding = NoopSpotifyPlaylistMetadataProvider()
) -> (
    viewModel: TimerViewModel,
    settingsStore: SettingsStore,
    defaults: UserDefaults,
    suiteName: String,
    notificationService: MockNotificationService
) {
    let (store, defaults, suiteName) = TestSettingsFactory.makeSettingsStore(seed: initialSettings)
    let notifications = MockNotificationService()
    let viewModel = TimerViewModel(
        settingsStore: store,
        notificationService: notifications,
        sessionSetupSuggester: NoopSessionSetupSuggester(),
        subtaskBreakdownSuggester: NoopSubtaskBreakdownSuggester(),
        focusMusicController: focusMusicController,
        spotifyMetadataProvider: spotifyMetadataProvider
    )
    return (viewModel, store, defaults, suiteName, notifications)
}
