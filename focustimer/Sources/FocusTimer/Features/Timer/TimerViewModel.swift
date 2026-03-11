import Foundation

@MainActor
final class TimerViewModel: ObservableObject {
    @Published var sessionTitle: String
    @Published var sessionEmoji: String
    @Published var sessionAccentHex: String
    @Published var tasks: [FocusTask]
    @Published var subTaskTimersEnabled: Bool
    @Published var focusMusicEnabled: Bool
    @Published var focusMusicProvider: FocusMusicProvider
    @Published var spotifyPlaylistURIOrURL: String
    @Published var aiEnabled: Bool
    @Published private(set) var focusMusicStatusMessage: String?
    @Published private(set) var isFocusMusicPlaying = false
    @Published private(set) var isFocusMusicMuted = false
    @Published private(set) var spotifyNowPlayingTrackTitle: String?
    @Published private(set) var spotifyNowPlayingArtistName: String?
    @Published private(set) var spotifyNowPlayingAlbumTitle: String?
    @Published private(set) var spotifyNowPlayingArtworkURL: URL?
    @Published private(set) var spotifyNowPlayingPositionSeconds: Double?
    @Published private(set) var spotifyNowPlayingDurationSeconds: Double?
    @Published private(set) var spotifyPlaylistMetadata: SpotifyPlaylistMetadata?
    @Published private(set) var spotifyPlaylistMetadataStatus: SpotifyPlaylistMetadataResult?
    @Published private(set) var isSpotifyPlaylistMetadataLoading = false
    @Published private(set) var isFallbackMusicActive = false
    @Published private(set) var fallbackChannels: [TiimoMusicChannel] = []
    @Published var defaultFallbackChannelID: String?
    @Published private(set) var canSwitchBackToSpotifySuggestion = false
    @Published private(set) var activeFocusMusicProvider: FocusMusicProvider = .spotify

    @Published var focusMinutes: Double
    @Published var breakMinutes: Double
    @Published var secondsRemaining: Int
    @Published private(set) var phaseDurationSeconds: Int
    @Published private(set) var completedTaskEventCounter = 0
    @Published var isRunning = false
    @Published var phase: SessionPhase = .focus

    private let settingsStore: SettingsStore
    private let notificationService: NotificationServicing
    private let sessionSetupSuggester: SessionSetupSuggesting
    private let subtaskBreakdownSuggester: SubtaskBreakdownSuggesting
    private let focusMusicController: FocusMusicControlling
    private let spotifyMetadataProvider: SpotifyPlaylistMetadataProviding
    private var timer: Timer?
    private var playbackStatePollTimer: Timer?
    private var pendingPlaybackRefreshTask: Task<Void, Never>?
    private var providerSwitchTask: Task<Void, Never>?
    private var isApplyingCloudUpdate = false
    private var taskIndicesBeforeCompletion: [UUID: Int] = [:]
    private var taskCanonicalOrder: [UUID: Int]

    private let minimumMinutes = 1
    private let maximumFocusMinutes = 180
    private let maximumBreakMinutes = 120
    private let playbackStatePollInterval: TimeInterval = 1

    init(
        settingsStore: SettingsStore,
        notificationService: NotificationServicing,
        sessionSetupSuggester: SessionSetupSuggesting = SessionSetupSuggester(),
        subtaskBreakdownSuggester: SubtaskBreakdownSuggesting = SubtaskBreakdownSuggester(),
        focusMusicController: FocusMusicControlling = HybridFocusMusicController(),
        spotifyMetadataProvider: SpotifyPlaylistMetadataProviding = SpotifyPlaylistMetadataService()
    ) {
        self.settingsStore = settingsStore
        self.notificationService = notificationService
        self.sessionSetupSuggester = sessionSetupSuggester
        self.subtaskBreakdownSuggester = subtaskBreakdownSuggester
        self.focusMusicController = focusMusicController
        self.spotifyMetadataProvider = spotifyMetadataProvider

        let settings = settingsStore.load()
        self.sessionTitle = settings.sessionTitle
        self.sessionEmoji = settings.sessionEmoji
        self.sessionAccentHex = settings.sessionAccentHex
        let initialTasks = Self.normalizedTasks(
            settings.subTasks,
            defaultEmoji: FocusTask.defaultEmoji,
            forceIncomplete: false
        )
        self.taskCanonicalOrder = Dictionary(uniqueKeysWithValues: initialTasks.enumerated().map { ($0.element.id, $0.offset) })
        self.tasks = initialTasks
        self.subTaskTimersEnabled = settings.subTaskTimersEnabled
        self.focusMusicEnabled = settings.focusMusicEnabled
        self.focusMusicProvider = settings.focusMusicProvider
        self.spotifyPlaylistURIOrURL = Self.normalizedPlaylistOrDefault(settings.spotifyPlaylistURIOrURL)
        self.defaultFallbackChannelID = settings.defaultFallbackMusicChannelID
        self.aiEnabled = settings.aiEnabled
        self.focusMinutes = Double(settings.focusMinutes)
        self.breakMinutes = Double(settings.breakMinutes)
        let initialActiveMinutes = settings.subTaskTimersEnabled
            ? initialTasks.first(where: { !$0.isDone })?.durationMinutes
            : nil
        let initialFocusSeconds = max(60, (initialActiveMinutes ?? settings.focusMinutes) * 60)
        self.secondsRemaining = initialFocusSeconds
        self.phaseDurationSeconds = initialFocusSeconds

        settingsStore.onExternalSettingsChange = { [weak self] settings in
            Task { @MainActor in
                self?.applyCloudSettings(settings)
            }
        }
        settingsStore.synchronizeFromCloudNow()

        if let hybridController = focusMusicController as? HybridFocusMusicStateProviding {
            hybridController.setPreferredProvider(focusMusicProvider)
            hybridController.setDefaultFallbackMusicChannelID(defaultFallbackChannelID)
        }
        syncMusicControllerState()
        notificationService.requestAuthorizationIfNeeded()
        refreshSpotifyPlaylistMetadataIfNeeded(force: true)
        prefetchFallbackChannelsIfPossible()
        startPlaybackStatePolling()
    }

    deinit {
        timer?.invalidate()
        playbackStatePollTimer?.invalidate()
        pendingPlaybackRefreshTask?.cancel()
        providerSwitchTask?.cancel()
        settingsStore.onExternalSettingsChange = nil
    }

    var timeText: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var currentProgress: Double {
        guard phaseDurationSeconds > 0 else { return 0 }
        let elapsed = max(0, phaseDurationSeconds - secondsRemaining)
        return min(1, max(0, Double(elapsed) / Double(phaseDurationSeconds)))
    }

    var activeFocusTask: FocusTask? {
        guard subTaskTimersEnabled else { return nil }
        return tasks.first(where: { !$0.isDone })
    }

    var timerDisplayTitle: String {
        activeFocusTask?.title ?? sessionTitle
    }

    var timerDisplayEmoji: String {
        activeFocusTask?.emoji ?? sessionEmoji
    }

    var timerDisplayAccentHex: String {
        activeFocusTask?.accentHex ?? sessionAccentHex
    }

    var shouldShowResetCTA: Bool {
        !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    var spotifyPlaylistDisplayLabel: String {
        let trimmed = spotifyPlaylistURIOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Focus Playlist" }

        if trimmed.hasPrefix("spotify:playlist:") {
            let id = trimmed.replacingOccurrences(of: "spotify:playlist:", with: "")
            if !id.isEmpty {
                return "Playlist • \(String(id.prefix(8)))"
            }
        }

        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           host.contains("spotify.com")
        {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let idx = parts.firstIndex(of: "playlist"), idx + 1 < parts.count {
                return "Playlist • \(String(parts[idx + 1].prefix(8)))"
            }
        }
        return "Focus Playlist"
    }

    var spotifyPlaylistCategoryLabel: String {
        spotifyPlaylistMetadata?.typeLabel ?? "Offentlig playliste"
    }

    var spotifyPlaylistResolvedTitle: String {
        spotifyPlaylistMetadata?.title ?? spotifyPlaylistDisplayLabel
    }

    var spotifyPlaylistCoverURL: URL? {
        spotifyPlaylistMetadata?.thumbnailURL
    }

    private var hasSpotifyTrackTitle: Bool {
        let title = spotifyNowPlayingTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !title.isEmpty
    }

    private var shouldShowSpotifyPlaylistMetadata: Bool {
        activeFocusMusicProvider == .spotify && !isFocusMusicPlaying && !hasSpotifyTrackTitle
    }

    private var preferredFallbackChannel: TiimoMusicChannel? {
        if let defaultFallbackChannelID,
           let channel = fallbackChannels.first(where: { $0.id == defaultFallbackChannelID })
        {
            return channel
        }
        if let lofi = fallbackChannels.first(where: { Self.isLofiChannelName($0.name) }) {
            return lofi
        }
        return fallbackChannels.first
    }

    var spotifyPlaybackCoverURL: URL? {
        if activeFocusMusicProvider == .tiimoRadio {
            return spotifyNowPlayingArtworkURL ?? preferredFallbackChannel?.coverURL
        }
        if shouldShowSpotifyPlaylistMetadata {
            return spotifyPlaylistCoverURL
        }
        return spotifyNowPlayingArtworkURL ?? spotifyPlaylistCoverURL
    }

    var spotifyPlaybackContextLabel: String {
        spotifyNowPlayingTrackTitle == nil ? spotifyPlaylistCategoryLabel : "Nu spiller"
    }

    var spotifyPlaybackPrimaryLabel: String {
        if activeFocusMusicProvider == .tiimoRadio {
            let fallbackNowPlaying = spotifyNowPlayingTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fallbackNowPlaying.isEmpty {
                return fallbackNowPlaying
            }
            return preferredFallbackChannel?.name ?? "Lo-Fi"
        }
        if shouldShowSpotifyPlaylistMetadata {
            return spotifyPlaylistResolvedTitle
        }
        return spotifyNowPlayingTrackTitle ?? spotifyPlaylistResolvedTitle
    }

    var spotifyPlaybackSecondaryLabel: String {
        let artist = spotifyNowPlayingArtistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = spotifyNowPlayingAlbumTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !artist.isEmpty && !album.isEmpty {
            return "\(artist) / \(album)"
        }
        if !artist.isEmpty {
            return artist
        }
        if !album.isEmpty {
            return album
        }
        if activeFocusMusicProvider == .tiimoRadio {
            return "Tiimo Radio"
        }
        if shouldShowSpotifyPlaylistMetadata {
            return ""
        }
        return ""
    }

    var spotifyPlaybackProgress: Double {
        if shouldShowSpotifyPlaylistMetadata {
            return 0
        }
        guard let position = spotifyNowPlayingPositionSeconds,
              let duration = spotifyNowPlayingDurationSeconds,
              duration > 0.5
        else {
            return 0
        }
        return min(1, max(0, position / duration))
    }

    var spotifyPlaybackElapsedLabel: String {
        if shouldShowSpotifyPlaylistMetadata {
            return "--:--"
        }
        return formattedPlaybackTime(spotifyNowPlayingPositionSeconds)
    }

    var spotifyPlaybackDurationLabel: String {
        if shouldShowSpotifyPlaylistMetadata {
            return "--:--"
        }
        return formattedPlaybackTime(spotifyNowPlayingDurationSeconds)
    }

    func currentTaskTemplate() -> TaskTemplate {
        let orderedTasks = tasks
            .enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = taskCanonicalOrder[lhs.element.id] ?? lhs.offset
                let rhsOrder = taskCanonicalOrder[rhs.element.id] ?? rhs.offset
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        let sanitizedTasks = Self.normalizedTasks(
            orderedTasks,
            defaultEmoji: FocusTask.defaultEmoji,
            forceIncomplete: true
        )

        let resolvedCategory = SessionCategory.match(in: sessionTitle) ?? SessionCategory.match(colorHex: sessionAccentHex)

        return TaskTemplate(
            title: sessionTitle,
            emoji: sessionEmoji,
            accentHex: sessionAccentHex,
            focusMinutes: Int(focusMinutes.rounded()),
            subTasks: sanitizedTasks,
            subTaskTimersEnabled: subTaskTimersEnabled,
            categoryName: resolvedCategory?.name,
            source: .user
        )
    }

    func applyTaskTemplate(_ template: TaskTemplate, startImmediately: Bool) {
        pauseTimer()

        applySessionIdentity(
            title: template.title,
            emoji: template.emoji,
            accentHex: template.accentHex
        )

        let sanitizedTasks = Self.normalizedTasks(
            template.subTasks,
            defaultEmoji: FocusTask.defaultEmoji,
            forceIncomplete: true
        )
        tasks = sanitizedTasks
        setCanonicalTaskOrder(from: sanitizedTasks)
        taskIndicesBeforeCompletion.removeAll()
        subTaskTimersEnabled = template.subTaskTimersEnabled && !sanitizedTasks.isEmpty
        focusMinutes = Double(clampedFocusMinutes(template.effectiveFocusMinutes))
        assertTaskInvariants()

        phase = .focus
        let focusSeconds = currentFocusPhaseDurationSeconds()
        phaseDurationSeconds = focusSeconds
        secondsRemaining = focusSeconds

        if startImmediately {
            startTimer()
        }

        persistSettings()
    }

    func toggleTimer() {
        if shouldShowResetCTA {
            resetCompletedSubtasksAndStart()
            return
        }

        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    func updateFocusMusicEnabled(_ enabled: Bool) {
        focusMusicEnabled = enabled
        persistSettings()
        if !enabled {
            isFocusMusicPlaying = false
            isFocusMusicMuted = false
            pauseFocusMusicManually()
            return
        }
        prefetchFallbackChannelsIfPossible()
        requestPlaybackStateRefreshSoon(delayNanoseconds: 120_000_000)
    }

    func updateSpotifyPlaylistURIOrURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            spotifyPlaylistURIOrURL = FocusSettings.default.spotifyPlaylistURIOrURL
            focusMusicStatusMessage = nil
            persistSettings()
            refreshSpotifyPlaylistMetadataIfNeeded(force: true)
            return true
        }

        guard SpotifyPlaybackController.normalizedPlaylistURI(from: trimmed) != nil else {
            focusMusicStatusMessage = "Invalid Spotify playlist link."
            spotifyPlaylistMetadataStatus = .invalidPlaylist
            return false
        }
        spotifyPlaylistURIOrURL = trimmed
        focusMusicStatusMessage = nil
        persistSettings()
        refreshSpotifyPlaylistMetadataIfNeeded(force: true)
        return true
    }

    func syncSpotifyPreviewToSavedPlaylistIfNeeded() {
        guard focusMusicEnabled,
              focusMusicProvider == .spotify,
              activeFocusMusicProvider == .spotify,
              !isFallbackMusicActive,
              !isFocusMusicPlaying
        else {
            requestPlaybackStateRefreshSoon(delayNanoseconds: 90_000_000)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let playResult = await self.focusMusicController.play(playlist: self.spotifyPlaylistURIOrURL)
            switch playResult {
            case .success:
                try? await Task.sleep(nanoseconds: 220_000_000)
                _ = await self.focusMusicController.pause()
                self.isFocusMusicPlaying = false
                self.requestPlaybackStateRefreshSoon(delayNanoseconds: 120_000_000)
            case .appNotInstalled, .permissionDenied, .invalidPlaylist, .commandFailed:
                self.applyMusicResult(playResult, context: .play)
            }
        }
    }

    func updateAIEnabled(_ enabled: Bool) {
        aiEnabled = enabled
        persistSettings()
    }

    func updateFocusMusicProvider(_ provider: FocusMusicProvider) {
        guard focusMusicProvider != provider else { return }
        let shouldResumePlayback = focusMusicEnabled && isFocusMusicPlaying

        focusMusicProvider = provider
        if let hybridController = focusMusicController as? HybridFocusMusicStateProviding {
            hybridController.setPreferredProvider(provider)
            syncMusicControllerState()
        } else {
            activeFocusMusicProvider = provider
        }
        prefetchFallbackChannelsIfPossible()
        persistSettings()

        providerSwitchTask?.cancel()
        providerSwitchTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if let hybridController = self.focusMusicController as? HybridFocusMusicStateProviding {
                await hybridController.pauseAllProvidersForSwitch()
            } else {
                _ = await self.focusMusicController.pause()
            }
            if Task.isCancelled { return }
            self.isFocusMusicPlaying = false

            if shouldResumePlayback {
                let result = await self.focusMusicController.play(playlist: self.spotifyPlaylistURIOrURL)
                if Task.isCancelled { return }
                self.applyMusicResult(result, context: .play)
            } else {
                self.requestPlaybackStateRefreshSoon(delayNanoseconds: 90_000_000)
            }
        }
    }

    func updateDefaultFallbackChannelID(_ id: String?) {
        defaultFallbackChannelID = id
        if let hybridController = focusMusicController as? HybridFocusMusicStateProviding {
            hybridController.setDefaultFallbackMusicChannelID(id)
            syncMusicControllerState()
        }
        persistSettings()
    }

    func switchBackToSpotifyFromFallback() {
        guard let hybridController = focusMusicController as? HybridFocusMusicStateProviding else { return }
        Task { @MainActor in
            if await hybridController.switchBackToSpotifyIfAvailable() {
                focusMusicStatusMessage = nil
                canSwitchBackToSpotifySuggestion = false
            } else {
                focusMusicStatusMessage = "Spotify is not installed."
            }
            syncMusicControllerState()
            requestPlaybackStateRefreshSoon(delayNanoseconds: 90_000_000)
        }
    }

    func clearFocusMusicStatusMessage() {
        focusMusicStatusMessage = nil
    }

    func refreshSpotifyPlaylistMetadataIfNeeded(force: Bool = false) {
        let normalized = spotifyPlaylistURIOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            spotifyPlaylistMetadata = nil
            spotifyPlaylistMetadataStatus = .invalidPlaylist
            return
        }
        if !force, spotifyPlaylistMetadata != nil {
            return
        }

        isSpotifyPlaylistMetadataLoading = true
        Task { @MainActor in
            let result = await spotifyMetadataProvider.fetchMetadata(for: normalized)
            spotifyPlaylistMetadataStatus = result
            switch result {
            case .success(let metadata):
                spotifyPlaylistMetadata = metadata
            case .invalidPlaylist:
                spotifyPlaylistMetadata = nil
            case .networkError, .decodingError, .rateLimited:
                break
            }
            isSpotifyPlaylistMetadataLoading = false
        }
    }

    func openSpotifyPlaylistPreview(_ playlist: String?) {
        guard focusMusicProvider == .spotify, !isFallbackMusicActive else { return }
        Task { @MainActor in
            let result = await focusMusicController.openInSpotify(playlist: playlist)
            applyMusicResult(result, context: .open)
        }
    }

    func playFocusMusicManually() {
        runMusicCommand(context: .play) { [self] in
            await self.focusMusicController.play(playlist: self.spotifyPlaylistURIOrURL)
        }
    }

    func pauseFocusMusicManually() {
        runMusicCommand(context: .pause) { [self] in
            await self.focusMusicController.pause()
        }
    }

    func toggleFocusMusicPlayback() {
        if isFocusMusicPlaying {
            pauseFocusMusicManually()
        } else {
            playFocusMusicManually()
        }
    }

    func toggleFocusMusicMuted() {
        let nextMutedState = !isFocusMusicMuted
        runMusicCommand(context: nextMutedState ? .mute : .unmute) { [self] in
            await self.focusMusicController.setMuted(nextMutedState)
        }
    }

    func nextFocusMusicTrack() {
        runMusicCommand(context: .next) { [self] in await self.focusMusicController.next() }
    }

    func previousFocusMusicTrack() {
        runMusicCommand(context: .previous) { [self] in await self.focusMusicController.previous() }
    }

    func seekFocusMusicBackward(seconds: Int = 10) {
        let delta = -abs(seconds)
        runMusicCommand(context: .seek) { [self] in await self.focusMusicController.seek(by: delta) }
    }

    func seekFocusMusicForward(seconds: Int = 10) {
        let delta = abs(seconds)
        runMusicCommand(context: .seek) { [self] in await self.focusMusicController.seek(by: delta) }
    }

    func decreaseFocusMusicVolume(step: Int = 8) {
        let delta = -abs(step)
        runMusicCommand(context: .volume) { [self] in await self.focusMusicController.adjustVolume(by: delta) }
    }

    func increaseFocusMusicVolume(step: Int = 8) {
        let delta = abs(step)
        runMusicCommand(context: .volume) { [self] in await self.focusMusicController.adjustVolume(by: delta) }
    }

    func resetTimer() {
        isRunning = false
        timer?.invalidate()
        phase = .focus
        let focusSeconds = currentFocusPhaseDurationSeconds()
        secondsRemaining = focusSeconds
        phaseDurationSeconds = focusSeconds
    }

    func addMinute() {
        secondsRemaining += 60
        phaseDurationSeconds += 60
    }

    func resetCompletedSubtasksAndStart() {
        guard shouldShowResetCTA else { return }

        pauseTimer()
        phase = .focus

        tasks = tasks.map { task in
            FocusTask(
                id: task.id,
                emoji: task.emoji,
                title: task.title,
                durationMinutes: task.durationMinutes,
                accentHex: task.accentHex,
                isDone: false
            )
        }
        setCanonicalTaskOrder(from: tasks)
        taskIndicesBeforeCompletion.removeAll()

        _ = applyActiveSubtaskDurationIfNeeded(resetRemaining: true)
        startTimer()
        persistSettings()
    }

    func updateFocusMinutes(_ value: Double) {
        focusMinutes = Double(clampedMinutes(value, min: minimumMinutes, max: maximumFocusMinutes))
        refreshPhaseDurationsForCurrentState(resetActiveTaskRemaining: true)
        persistSettings()
    }

    func updateBreakMinutes(_ value: Double) {
        breakMinutes = Double(clampedMinutes(value, min: minimumMinutes, max: maximumBreakMinutes))
        if phase == .rest {
            resyncCurrentPhaseAfterDurationChange(newDurationMinutes: Int(breakMinutes))
        } else {
            syncWhenStopped()
        }
        persistSettings()
    }

    func updateSessionTitle(_ value: String) {
        sessionTitle = normalizedSessionTitle(value)
        persistSettings()
    }

    func updateSessionEmoji(_ value: String) {
        sessionEmoji = normalizedSessionEmoji(value)
        persistSettings()
    }

    func updateSessionAccentHex(_ value: String) {
        sessionAccentHex = HexColor.normalize(value) ?? FocusSettings.default.sessionAccentHex
        persistSettings()
    }

    func updateSubTaskTimersEnabled(_ enabled: Bool) {
        subTaskTimersEnabled = enabled
        if enabled, let total = subTaskTotalMinutes() {
            updateFocusMinutes(Double(total))
            return
        }

        if phase == .focus {
            resyncCurrentPhaseAfterDurationChange(newDurationMinutes: Int(focusMinutes))
        } else {
            syncWhenStopped()
        }

        persistSettings()
    }

    func updateTasks(_ value: [FocusTask]) {
        tasks = Self.normalizedTasks(
            value,
            defaultEmoji: FocusTask.defaultEmoji,
            forceIncomplete: false
        )
        setCanonicalTaskOrder(from: tasks)
        taskIndicesBeforeCompletion.removeAll()
        assertTaskInvariants()
        if subTaskTimersEnabled, let total = subTaskTotalMinutes() {
            updateFocusMinutes(Double(total))
            return
        }

        refreshPhaseDurationsForCurrentState(resetActiveTaskRemaining: true)

        persistSettings()
    }

    func suggestSessionSetup(prompt: String, current: SessionSetupSuggestion) async -> SessionSetupSuggestion? {
        guard aiEnabled else { return nil }
        return await sessionSetupSuggester.suggest(from: prompt, current: current)
    }

    func applySmartSessionSetup(prompt: String) async -> Bool {
        guard aiEnabled else { return false }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return false }

        let current = SessionSetupSuggestion(
            title: sessionTitle,
            emoji: sessionEmoji,
            focusMinutes: Int(focusMinutes),
            accentHex: sessionAccentHex
        )
        guard let suggested = await sessionSetupSuggester.suggest(from: trimmedPrompt, current: current) else {
            return false
        }

        applySessionIdentity(
            title: suggested.title,
            emoji: suggested.emoji,
            accentHex: suggested.accentHex
        )
        focusMinutes = Double(clampedFocusMinutes(suggested.focusMinutes))
        refreshPhaseDurationsForCurrentState(resetActiveTaskRemaining: true)

        persistSettings()
        return true
    }

    func toggleTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone.toggle()
        let isNowDone = tasks[index].isDone

        if isNowDone {
            taskIndicesBeforeCompletion[id] = index
            let completedTask = tasks.remove(at: index)
            tasks.append(completedTask)
            completedTaskEventCounter += 1

            if shouldShowResetCTA {
                handleAllSubtasksCompleted()
                persistSettings()
                return
            }
        } else {
            let restoredIndex = taskIndicesBeforeCompletion.removeValue(forKey: id) ?? index
            let reopenedTask = tasks.remove(at: index)
            let targetIndex = min(max(0, restoredIndex), tasks.count)
            tasks.insert(reopenedTask, at: targetIndex)
        }

        refreshPhaseDurationsForCurrentState(resetActiveTaskRemaining: true)

        persistSettings()
        assertTaskInvariants()
    }

    func suggestSubtasks(title: String, totalMinutes: Int, current: [FocusTask]) async -> [FocusTask]? {
        guard aiEnabled else { return nil }
        return await subtaskBreakdownSuggester.suggestSubtasks(
            title: title,
            totalMinutes: totalMinutes,
            current: current
        )
    }

    private func startTimer() {
        if phase == .focus {
            _ = applyActiveSubtaskDurationIfNeeded(resetRemaining: false)
        }
        isRunning = true
        scheduleTimer()

        guard focusMusicEnabled else { return }
        Task { @MainActor in
            let result = await focusMusicController.play(playlist: spotifyPlaylistURIOrURL)
            applyMusicResult(result, context: .play)
        }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.tick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func startPlaybackStatePolling() {
        playbackStatePollTimer?.invalidate()
        playbackStatePollTimer = Timer.scheduledTimer(withTimeInterval: playbackStatePollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                await self.refreshPlaybackStateNow()
            }
        }
        if let playbackStatePollTimer {
            RunLoop.main.add(playbackStatePollTimer, forMode: .common)
        }
        requestPlaybackStateRefreshSoon(delayNanoseconds: 0)
    }

    private func requestPlaybackStateRefreshSoon(delayNanoseconds: UInt64) {
        pendingPlaybackRefreshTask?.cancel()
        pendingPlaybackRefreshTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if Task.isCancelled { return }
            guard let self else { return }
            await self.refreshPlaybackStateNow()
        }
    }

    private func refreshPlaybackStateNow() async {
        guard focusMusicEnabled else { return }

        syncMusicControllerState()
        guard let snapshot = await focusMusicController.playbackSnapshot() else {
            isFocusMusicPlaying = false
            clearNowPlayingSnapshot()
            return
        }

        isFocusMusicPlaying = snapshot.isPlaying
        isFocusMusicMuted = snapshot.isMuted
        spotifyNowPlayingTrackTitle = snapshot.trackTitle
        spotifyNowPlayingArtistName = snapshot.artistName
        spotifyNowPlayingAlbumTitle = snapshot.albumTitle
        spotifyNowPlayingArtworkURL = snapshot.artworkURL
        spotifyNowPlayingPositionSeconds = snapshot.playbackPositionSeconds
        spotifyNowPlayingDurationSeconds = snapshot.trackDurationSeconds
    }

    private func tick() {
        guard isRunning else { return }

        if secondsRemaining > 0 {
            secondsRemaining -= 1
            return
        }

        if phase == .focus, subTaskTimersEnabled, let activeTaskID = activeFocusTask?.id {
            toggleTask(id: activeTaskID)
            if activeFocusTask != nil || shouldShowResetCTA {
                return
            }
        }

        phase = phase == .focus ? .rest : .focus
        phaseDurationSeconds = currentPhaseDurationSeconds()
        secondsRemaining = phaseDurationSeconds
        notificationService.notifyPhaseChange(
            phase: phase,
            minutes: phase == .focus ? currentFocusPhaseDurationMinutes() : Int(breakMinutes)
        )
    }

    private func syncWhenStopped() {
        guard !isRunning else { return }
        phaseDurationSeconds = currentPhaseDurationSeconds()
        secondsRemaining = phaseDurationSeconds
    }

    private func refreshPhaseDurationsForCurrentState(resetActiveTaskRemaining: Bool) {
        if phase == .focus {
            if subTaskTimersEnabled,
               applyActiveSubtaskDurationIfNeeded(resetRemaining: resetActiveTaskRemaining)
            {
                return
            }
            resyncCurrentPhaseAfterDurationChange(newDurationMinutes: Int(focusMinutes))
            return
        }

        syncWhenStopped()
    }

    private func handleAllSubtasksCompleted() {
        pauseTimer()
        phase = .focus
        let routineDurationSeconds = max(60, Int(focusMinutes.rounded()) * 60)
        phaseDurationSeconds = routineDurationSeconds
        secondsRemaining = routineDurationSeconds
    }

    private func resyncCurrentPhaseAfterDurationChange(newDurationMinutes: Int) {
        let newDurationSeconds = max(60, newDurationMinutes * 60)
        if isRunning {
            let elapsed = max(0, phaseDurationSeconds - secondsRemaining)
            phaseDurationSeconds = newDurationSeconds
            secondsRemaining = max(0, newDurationSeconds - elapsed)
        } else {
            phaseDurationSeconds = newDurationSeconds
            secondsRemaining = newDurationSeconds
        }
    }

    private func currentFocusPhaseDurationMinutes() -> Int {
        if let activeMinutes = activeFocusTask?.durationMinutes {
            return max(1, activeMinutes)
        }
        return max(minimumMinutes, Int(focusMinutes.rounded()))
    }

    private func currentFocusPhaseDurationSeconds() -> Int {
        max(60, currentFocusPhaseDurationMinutes() * 60)
    }

    private func currentPhaseDurationSeconds() -> Int {
        if phase == .focus {
            return currentFocusPhaseDurationSeconds()
        }
        return max(60, Int(breakMinutes.rounded()) * 60)
    }

    @discardableResult
    private func applyActiveSubtaskDurationIfNeeded(resetRemaining: Bool) -> Bool {
        guard phase == .focus, let activeTask = activeFocusTask else { return false }
        let newDurationSeconds = max(60, activeTask.durationMinutes * 60)
        phaseDurationSeconds = newDurationSeconds
        if resetRemaining {
            secondsRemaining = newDurationSeconds
        } else {
            secondsRemaining = min(secondsRemaining, newDurationSeconds)
        }
        return true
    }

    private func persistSettings() {
        guard !isApplyingCloudUpdate else { return }
        settingsStore.save(currentSettings())
    }

    private func currentSettings() -> FocusSettings {
        let clampedFocus = clampedFocusMinutes(Int(focusMinutes.rounded()))
        let clampedBreak = clampedBreakMinutes(Int(breakMinutes.rounded()))
        return FocusSettings(
            focusMinutes: subTaskTimersEnabled ? (subTaskTotalMinutes() ?? clampedFocus) : clampedFocus,
            breakMinutes: clampedBreak,
            sessionTitle: sessionTitle,
            sessionEmoji: sessionEmoji,
            sessionAccentHex: sessionAccentHex,
            subTasks: Self.normalizedTasks(
                tasks,
                defaultEmoji: FocusTask.defaultEmoji,
                forceIncomplete: false
            ),
            subTaskTimersEnabled: subTaskTimersEnabled,
            focusMusicEnabled: focusMusicEnabled,
            focusMusicProvider: focusMusicProvider,
            spotifyPlaylistURIOrURL: spotifyPlaylistURIOrURL,
            defaultFallbackMusicChannelID: defaultFallbackChannelID,
            aiEnabled: aiEnabled
        )
    }

    private func applyCloudSettings(_ settings: FocusSettings) {
        guard settings != currentSettings() else { return }

        isApplyingCloudUpdate = true
        applySessionIdentity(
            title: settings.sessionTitle,
            emoji: settings.sessionEmoji,
            accentHex: settings.sessionAccentHex
        )
        tasks = Self.normalizedTasks(
            settings.subTasks,
            defaultEmoji: FocusTask.defaultEmoji,
            forceIncomplete: false
        )
        setCanonicalTaskOrder(from: tasks)
        taskIndicesBeforeCompletion.removeAll()
        subTaskTimersEnabled = settings.subTaskTimersEnabled
        focusMusicEnabled = settings.focusMusicEnabled
        focusMusicProvider = settings.focusMusicProvider
        spotifyPlaylistURIOrURL = settings.spotifyPlaylistURIOrURL
        spotifyPlaylistURIOrURL = Self.normalizedPlaylistOrDefault(spotifyPlaylistURIOrURL)
        defaultFallbackChannelID = settings.defaultFallbackMusicChannelID
        if let hybridController = focusMusicController as? HybridFocusMusicStateProviding {
            hybridController.setPreferredProvider(focusMusicProvider)
            hybridController.setDefaultFallbackMusicChannelID(defaultFallbackChannelID)
        }
        aiEnabled = settings.aiEnabled
        refreshSpotifyPlaylistMetadataIfNeeded(force: true)
        syncMusicControllerState()
        prefetchFallbackChannelsIfPossible()
        let effectiveFocus = subTaskTimersEnabled ? (subTaskTotalMinutes() ?? settings.focusMinutes) : settings.focusMinutes
        focusMinutes = Double(clampedFocusMinutes(effectiveFocus))
        breakMinutes = Double(clampedBreakMinutes(settings.breakMinutes))
        syncWhenStopped()
        assertTaskInvariants()
        isApplyingCloudUpdate = false
    }

    private func subTaskTotalMinutes() -> Int? {
        guard !tasks.isEmpty else { return nil }
        return tasks.reduce(0) { $0 + max(1, $1.durationMinutes) }
    }

    private func clampedMinutes(_ value: Double, min minMinutes: Int, max maxMinutes: Int) -> Int {
        min(maxMinutes, max(minMinutes, Int(value.rounded())))
    }

    private func clampedFocusMinutes(_ value: Int) -> Int {
        min(maximumFocusMinutes, max(minimumMinutes, value))
    }

    private func clampedBreakMinutes(_ value: Int) -> Int {
        min(maximumBreakMinutes, max(minimumMinutes, value))
    }

    private func applySessionIdentity(title: String, emoji: String, accentHex: String) {
        sessionTitle = normalizedSessionTitle(title)
        sessionEmoji = normalizedSessionEmoji(emoji)
        sessionAccentHex = HexColor.normalize(accentHex) ?? FocusSettings.default.sessionAccentHex
    }

    private func normalizedSessionTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? FocusSettings.default.sessionTitle : trimmed
    }

    private func normalizedSessionEmoji(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.firstEmojiLike() ?? FocusSettings.default.sessionEmoji
    }

    private func formattedPlaybackTime(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private static func normalizedTasks(
        _ tasks: [FocusTask],
        defaultEmoji: String,
        forceIncomplete: Bool
    ) -> [FocusTask] {
        var seenIDs = Set<UUID>()
        var normalized: [FocusTask] = []
        normalized.reserveCapacity(tasks.count)

        for task in tasks {
            let normalizedID: UUID = {
                if seenIDs.insert(task.id).inserted {
                    return task.id
                }
                var candidate = UUID()
                while !seenIDs.insert(candidate).inserted {
                    candidate = UUID()
                }
                return candidate
            }()

            let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = trimmedTitle.isEmpty ? FocusTask.defaultTitle : trimmedTitle
            let normalizedEmoji = task.emoji.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike() ?? defaultEmoji
            let normalizedDuration = min(120, max(1, task.durationMinutes))
            let normalizedAccentHex = HexColor.normalize(task.accentHex) ?? FocusSettings.default.sessionAccentHex

            normalized.append(
                FocusTask(
                    id: normalizedID,
                    emoji: normalizedEmoji,
                    title: normalizedTitle,
                    durationMinutes: normalizedDuration,
                    accentHex: normalizedAccentHex,
                    isDone: forceIncomplete ? false : task.isDone
                )
            )
        }

        return normalized
    }

    private static func normalizedPlaylistOrDefault(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? FocusSettings.default.spotifyPlaylistURIOrURL : trimmed
    }

    private func setCanonicalTaskOrder(from tasks: [FocusTask]) {
        taskCanonicalOrder = Dictionary(uniqueKeysWithValues: tasks.enumerated().map { ($0.element.id, $0.offset) })
    }

    private static func isLofiChannelName(_ name: String) -> Bool {
        let normalized = name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return normalized.contains("lofi")
    }

    private func assertTaskInvariants() {
        #if DEBUG
        let uniqueCount = Set(tasks.map(\.id)).count
        assert(uniqueCount == tasks.count, "Task IDs must be unique")
        assert(tasks.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "Task titles must be non-empty")
        assert(tasks.allSatisfy { (1...120).contains($0.durationMinutes) }, "Task durations must be clamped to 1...120")
        #endif
    }

    private func runMusicCommand(
        context: MusicCommandContext,
        operation: @escaping @MainActor () async -> FocusMusicControlResult
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await operation()
            self.applyMusicResult(result, context: context)
        }
    }

    private func clearNowPlayingSnapshot() {
        spotifyNowPlayingTrackTitle = nil
        spotifyNowPlayingArtistName = nil
        spotifyNowPlayingAlbumTitle = nil
        spotifyNowPlayingArtworkURL = nil
        spotifyNowPlayingPositionSeconds = nil
        spotifyNowPlayingDurationSeconds = nil
    }

    private enum MusicCommandContext {
        case play
        case pause
        case next
        case previous
        case seek
        case volume
        case open
        case mute
        case unmute
    }

    private func applyMusicResult(_ result: FocusMusicControlResult, context: MusicCommandContext) {
        syncMusicControllerState()
        switch result {
        case .success:
            focusMusicStatusMessage = nil
            switch context {
            case .play:
                isFocusMusicPlaying = true
            case .pause:
                isFocusMusicPlaying = false
            case .mute:
                isFocusMusicMuted = true
            case .unmute:
                isFocusMusicMuted = false
            case .next, .previous, .seek, .volume, .open:
                break
            }
            requestPlaybackStateRefreshSoon(delayNanoseconds: 180_000_000)
        case .appNotInstalled:
            focusMusicStatusMessage = "Spotify is not installed."
        case .permissionDenied:
            focusMusicStatusMessage = "Spotify control limited. Allow Automation in System Settings."
        case .invalidPlaylist:
            focusMusicStatusMessage = "Invalid Spotify playlist link."
        case .commandFailed(let message):
            let fallbackContext: String
            switch context {
            case .play: fallbackContext = "play"
            case .pause: fallbackContext = "pause"
            case .next: fallbackContext = "skip"
            case .previous: fallbackContext = "previous"
            case .seek: fallbackContext = "seek"
            case .volume: fallbackContext = "adjust volume"
            case .open: fallbackContext = "open"
            case .mute: fallbackContext = "mute"
            case .unmute: fallbackContext = "unmute"
            }
            if isFallbackMusicActive {
                focusMusicStatusMessage = "Could not \(fallbackContext) fallback music (\(message))."
            } else {
                focusMusicStatusMessage = "Could not \(fallbackContext) Spotify (\(message))."
            }
        }
    }

    private func prefetchFallbackChannelsIfPossible() {
        guard let hybridController = focusMusicController as? HybridFocusMusicStateProviding else { return }
        Task { @MainActor in
            await hybridController.refreshFallbackChannels()
            syncMusicControllerState()
        }
    }

    private func syncMusicControllerState() {
        guard let hybridController = focusMusicController as? HybridFocusMusicStateProviding else {
            isFallbackMusicActive = false
            fallbackChannels = []
            canSwitchBackToSpotifySuggestion = false
            activeFocusMusicProvider = focusMusicProvider
            return
        }
        isFallbackMusicActive = hybridController.isUsingFallbackMusic
        fallbackChannels = hybridController.fallbackChannels
        canSwitchBackToSpotifySuggestion = hybridController.canSwitchBackToSpotifyNow
        activeFocusMusicProvider = hybridController.activeProvider
        let previousDefaultFallbackID = defaultFallbackChannelID
        if defaultFallbackChannelID == nil {
            if let suggested = hybridController.defaultFallbackMusicChannelID {
                defaultFallbackChannelID = suggested
            } else if let suggested = preferredFallbackChannel?.id {
                defaultFallbackChannelID = suggested
                hybridController.setDefaultFallbackMusicChannelID(suggested)
            }
        }
        if defaultFallbackChannelID != previousDefaultFallbackID,
           defaultFallbackChannelID != nil
        {
            persistSettings()
        }
    }
}
