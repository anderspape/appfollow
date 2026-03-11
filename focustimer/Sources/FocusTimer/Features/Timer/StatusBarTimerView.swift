import SwiftUI
import UniformTypeIdentifiers
import EmojiKit

struct StatusBarTimerView: View {
        @ObservedObject var viewModel: TimerViewModel
    @ObservedObject private var navigationBridge: StatusBarNavigationBridge
    private let taskLibraryStore: TaskLibraryStore
    private let premadeTaskCatalog: PremadeTaskCatalog
    var onPreferredSizeChange: ((CGSize) -> Void)?
    var onSettingsVisibilityChange: ((Bool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TimerFrontDisplayMode.storageKey) private var timerFrontDisplayModeRawValue = TimerFrontDisplayMode.full.rawValue

    // MARK: - View State

    @State private var isShowingSettings = false
    @State private var draftTitle = FocusSettings.default.sessionTitle
    @State private var draftEmoji = FocusSettings.default.sessionEmoji
    @State private var draftFocusMinutes = FocusSettings.default.focusMinutes
    @State private var draftAccentHex = FocusSettings.default.sessionAccentHex
    @State private var draftTasks = FocusSettings.default.subTasks
    @State private var draftSubTaskTimersEnabled = FocusSettings.default.subTaskTimersEnabled
    @State private var appSettingsSpotifyPlaylistDraft = FocusSettings.default.spotifyPlaylistURIOrURL
    @State private var isSavingSession = false
    @State private var isLiveSuggesting = false
    @State private var isAutoSuggestingSubtasks = false
    @State private var isEmojiPickerPresented = false
    @State private var isDurationPickerPresented = false
    @State private var editingTaskDurationID: UUID?
    @State private var editingTaskVisualID: UUID?
    @State private var suggestionTaskBag = SuggestionTaskBag()
    @State private var suggestionGate = SuggestionRequestGate<SuggestionTaskBag.Key>()
    @State private var draggedTaskID: UUID?
    @State private var hoveredTaskID: UUID?
    @State private var emojiGridCategory: EmojiCategory?
    @State private var emojiGridSelection: Emoji.GridSelection?
    @State private var subtaskEmojiGridCategory: EmojiCategory?
    @State private var subtaskEmojiGridSelection: Emoji.GridSelection?
    @FocusState private var focusedSubtaskID: UUID?
    @State private var measuredTimerContentHeight: CGFloat = 450
    @State private var measuredSettingsContentHeight: CGFloat = 450
    @State private var measuredEditTaskContentHeight: CGFloat = 450
    @State private var measuredLibraryContentHeight: CGFloat = 378
    @State private var isShowingTaskLibrary = false
    @State private var isShowingTaskEditor = false
    @State private var userTaskLibraryTemplates: [TaskTemplate] = []
    @State private var premadeTaskLibraryTemplates: [TaskTemplate] = []
    @State private var savedPremadeTemplateIDs: Set<String> = []
    @State private var librarySelectedTab: StatusBarTaskLibraryDrawer.TaskLibraryTab = .explore
    @State private var librarySelectedCategoryName: String?
    @State private var libraryCurrentPage = 0
    @State private var isEditingNewTask = false
    @State private var screenTransitionDirection: StatusBarTimerScreenTransitionDirection = .toTrailing
    @State private var isUnsavedChangesAlertPresented = false
    @State private var pendingNavigationTarget: StatusBarTimerScreen?
    @State private var appSettingsStatusMessage: String?

    init(
        viewModel: TimerViewModel,
        navigationBridge: StatusBarNavigationBridge,
        taskLibraryStore: TaskLibraryStore = TaskLibraryStore(),
        premadeTaskCatalog: PremadeTaskCatalog = PremadeTaskCatalog(),
        onPreferredSizeChange: ((CGSize) -> Void)? = nil,
        onSettingsVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        _navigationBridge = ObservedObject(wrappedValue: navigationBridge)
        self.taskLibraryStore = taskLibraryStore
        self.premadeTaskCatalog = premadeTaskCatalog
        self.onPreferredSizeChange = onPreferredSizeChange
        self.onSettingsVisibilityChange = onSettingsVisibilityChange
        _measuredTimerContentHeight = State(
            initialValue: StatusBarTimerLayoutMetrics.estimatedInitialTimerContentHeight(taskCount: viewModel.tasks.count)
        )
    }

    // MARK: - Derived Values

    private var ringProgress: Double {
        min(max(viewModel.currentProgress, 0), 1)
    }

    private var displayedRingProgress: Double {
        if ringProgress > 0 { return ringProgress }
        return viewModel.isRunning ? ringProgress : 0.035
    }

    private var theme: StatusBarTimerTheme {
        StatusBarTimerTheme(colorScheme: colorScheme)
    }

    private var primaryTextColor: Color {
        theme.primaryTextColor
    }

    private var emojiBackgroundColor: Color {
        Color(hex: viewModel.timerDisplayAccentHex) ?? theme.ringProgressColor
    }

    private var settingsCardBackground: Color {
        theme.settingsCardBackground
    }

    private var settingsPillBackground: Color {
        theme.settingsPillBackground
    }

    private var settingsDividerColor: Color {
        theme.settingsDividerColor
    }

    private var settingsSecondaryTextColor: Color {
        theme.secondaryTextColor
    }

    private var aiStatus: SessionSetupAIStatus {
        if !viewModel.aiEnabled {
            return SessionSetupAIStatus(
                isAvailable: false,
                title: "AI is disabled",
                detail: "AI suggestions are turned off."
            )
        }
        return SessionSetupAIAvailability.currentStatus
    }

    private var categoryColorHexes: [String] {
        SessionCategory.colorPaletteHexes
    }

    private var normalizedDraftAccentHex: String {
        HexColor.normalize(draftAccentHex) ?? FocusSettings.default.sessionAccentHex
    }

    private var subtaskMinutesTotal: Int {
        draftTasks.reduce(0) { $0 + max(1, $1.durationMinutes) }
    }

    private var effectiveDraftFocusMinutes: Int {
        if draftSubTaskTimersEnabled, subtaskMinutesTotal > 0 {
            return subtaskMinutesTotal
        }
        return draftFocusMinutes
    }

    private var panelWidth: CGFloat { theme.panelWidth }
    private var innerCardCornerRadius: CGFloat { theme.innerCardCornerRadius }
    private var panelInnerPadding: CGFloat { theme.panelInnerPadding }

    private var cardCornerRadius: CGFloat {
        theme.cardCornerRadius
    }

    private var panelCornerRadius: CGFloat {
        theme.panelCornerRadius
    }

    private var contentVerticalPadding: CGFloat {
        panelInnerPadding * 2
    }

    private var panelOuterPadding: CGFloat {
        activeScreen == .timer && timerFrontDisplayMode == .minified ? 0 : panelInnerPadding
    }

    private var timerFrontDisplayMode: TimerFrontDisplayMode {
        TimerFrontDisplayMode.fromStoredValue(timerFrontDisplayModeRawValue)
    }

    private var panelHeightContext: StatusBarPanelContext {
        if activeScreen == .timer && timerFrontDisplayMode == .minified {
            return .timerMinified
        }
        if activeScreen == .timer {
            return .timerFull(focusMusicEnabled: viewModel.focusMusicEnabled)
        }
        return .nonTimer
    }

    private var activeCardHeight: CGFloat {
        let contentHeight: CGFloat
        if isShowingSettings {
            contentHeight = measuredSettingsContentHeight
        } else if isShowingTaskEditor {
            contentHeight = measuredEditTaskContentHeight
        } else if isShowingTaskLibrary {
            contentHeight = measuredLibraryContentHeight
        } else {
            contentHeight = measuredTimerContentHeight
        }

        return StatusBarPanelHeightPolicy.preferredHeight(
            contentHeight: contentHeight,
            panelOuterPadding: panelOuterPadding,
            contentVerticalPadding: contentVerticalPadding,
            context: panelHeightContext
        )
    }

    private var preferredPanelSize: CGSize {
        CGSize(width: panelWidth, height: activeCardHeight)
    }

    private var currentTaskID: UUID? {
        viewModel.tasks.first(where: { !$0.isDone })?.id
    }

    private var isPanelInteractionLocked: Bool {
        isShowingSettings || isShowingTaskEditor
    }

    private var activeScreen: StatusBarTimerScreen {
        if isShowingSettings { return .settings }
        if isShowingTaskEditor { return .editTask }
        if isShowingTaskLibrary { return .library }
        return .timer
    }

    private var activeMeasuredView: StatusBarTimerMeasuredView {
        switch activeScreen {
        case .timer: return .timer
        case .settings: return .settings
        case .editTask: return .editTask
        case .library: return .library
        }
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: screenTransitionDirection.insertionEdge)),
            removal: .opacity.combined(with: .move(edge: screenTransitionDirection.removalEdge))
        )
    }

    private var hasUnsavedChanges: Bool {
        if isEditingNewTask {
            return hasStartedNewTaskDraft
        }

        let draftNormalizedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentNormalizedTitle = viewModel.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftNormalizedEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(draftEmoji, fallback: FocusSettings.default.sessionEmoji)
        let currentNormalizedEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(viewModel.sessionEmoji, fallback: FocusSettings.default.sessionEmoji)
        let draftNormalizedMinutes = max(1, effectiveDraftFocusMinutes)
        let currentNormalizedMinutes = max(1, Int(viewModel.focusMinutes.rounded()))
        let currentAccentHex = HexColor.normalize(viewModel.sessionAccentHex) ?? FocusSettings.default.sessionAccentHex
        let draftNormalizedTasks = StatusBarTimerDraftHelpers.normalizedTasks(draftTasks)
        let currentNormalizedTasks = StatusBarTimerDraftHelpers.normalizedTasks(viewModel.tasks)

        return draftNormalizedTitle != currentNormalizedTitle
            || draftNormalizedEmoji != currentNormalizedEmoji
            || draftNormalizedMinutes != currentNormalizedMinutes
            || normalizedDraftAccentHex != currentAccentHex
            || draftSubTaskTimersEnabled != viewModel.subTaskTimersEnabled
            || draftNormalizedTasks != currentNormalizedTasks
    }

    private var hasStartedNewTaskDraft: Bool {
        let normalizedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmojiValue = StatusBarTimerDraftHelpers.normalizedEmoji(draftEmoji, fallback: FocusSettings.default.sessionEmoji)
        let normalizedMinutes = max(1, effectiveDraftFocusMinutes)

        return !normalizedTitle.isEmpty
            || normalizedEmojiValue != FocusSettings.default.sessionEmoji
            || normalizedMinutes != FocusSettings.default.focusMinutes
            || normalizedDraftAccentHex != FocusSettings.default.sessionAccentHex
            || draftSubTaskTimersEnabled
            || !StatusBarTimerDraftHelpers.normalizedTasks(draftTasks).isEmpty
    }

    private var isCurrentFocusFavorite: Bool {
        userFavoriteSignatures.contains(viewModel.currentTaskTemplate().favoriteSignature)
    }

    private var userFavoriteSignatures: Set<String> {
        Set(userTaskLibraryTemplates.map(\.favoriteSignature))
    }

    private let liveSuggestionDebounceNanoseconds: UInt64 = 700_000_000
    private let liveSuggestionMinimumLetterCount = 3
    private let subtaskLiveSuggestionDebounceNanoseconds: UInt64 = 450_000_000
    private let subtaskLiveSuggestionMinimumLetterCount = 2
    private let primaryNavigationAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)
    private let drawerNavigationAnimation = Animation.spring(response: 0.38, dampingFraction: 0.9)

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                activeScreenContent
                    .readSize { size in
                        updateMeasuredContentHeight(size.height, for: activeMeasuredView)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(screenTransition)
            }
        }
        .padding(panelOuterPadding)
        .frame(width: panelWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(StatusBarGlassSurface(cornerRadius: panelCornerRadius, clipContent: false))
        .animation(.easeInOut(duration: 0.22), value: isShowingSettings)
        .animation(.easeInOut(duration: 0.2), value: isShowingTaskLibrary)
        .onAppear {
            taskLibraryStore.onExternalLibraryChange = { _, _ in
                Task { @MainActor in
                    refreshTaskLibrary()
                }
            }
            taskLibraryStore.synchronizeFromCloudNow()
            refreshTaskLibrary()
            notifyPreferredSizeChange()
            onSettingsVisibilityChange?(isPanelInteractionLocked)
        }
        .onDisappear {
            cancelLiveSuggestion()
            cancelAllSubtaskSuggestions()
            suggestionTaskBag.cancelAll()
            taskLibraryStore.onExternalLibraryChange = nil
        }
        .onChange(of: activeCardHeight) { _ in
            notifyPreferredSizeChange()
        }
        .onChange(of: isShowingSettings) { _ in
            notifyPreferredSizeChange()
            onSettingsVisibilityChange?(isPanelInteractionLocked)
        }
        .onChange(of: isShowingTaskEditor) { _ in
            notifyPreferredSizeChange()
            onSettingsVisibilityChange?(isPanelInteractionLocked)
        }
        .onChange(of: isShowingTaskLibrary) { _ in
            notifyPreferredSizeChange()
            onSettingsVisibilityChange?(isPanelInteractionLocked)
        }
        .onChange(of: viewModel.tasks.count) { _ in
            notifyPreferredSizeChange()
        }
        .onChange(of: viewModel.subTaskTimersEnabled) { _ in
            notifyPreferredSizeChange()
        }
        .onChange(of: timerFrontDisplayModeRawValue) { _ in
            notifyPreferredSizeChange()
        }
        .onChange(of: navigationBridge.commandVersion) { _ in
            handleExternalNavigationCommand(navigationBridge.latestCommand)
        }
        .onChange(of: draftTasks.map(\.id)) { taskIDs in
            if let focusedSubtaskID, !taskIDs.contains(focusedSubtaskID) {
                self.focusedSubtaskID = nil
            }
            if let editingTaskDurationID, !taskIDs.contains(editingTaskDurationID) {
                self.editingTaskDurationID = nil
            }
            if let editingTaskVisualID, !taskIDs.contains(editingTaskVisualID) {
                self.editingTaskVisualID = nil
            }
            if let hoveredTaskID, !taskIDs.contains(hoveredTaskID) {
                self.hoveredTaskID = nil
            }
            if let draggedTaskID, !taskIDs.contains(draggedTaskID) {
                self.draggedTaskID = nil
            }
            cancelSuggestionTasksForDeletedSubtasks(currentTaskIDs: Set(taskIDs))
        }
        .alert("Do you want to save?", isPresented: $isUnsavedChangesAlertPresented) {
            Button("Save") {
                let target = pendingNavigationTarget ?? .timer
                pendingNavigationTarget = nil
                saveSessionChanges(afterSaveScreen: target)
            }
            Button("Discard changes", role: .destructive) {
                let target = pendingNavigationTarget ?? .timer
                pendingNavigationTarget = nil
                cancelLiveSuggestion()
                cancelAllSubtaskSuggestions()
                dismissPickers()
                prepareDrafts()
                navigate(to: target, animation: primaryNavigationAnimation)
            }
            Button("Cancel", role: .cancel) {
                pendingNavigationTarget = nil
            }
        } message: {
            Text("You have unsaved changes.")
        }
    }

        @ViewBuilder
    private var activeScreenContent: some View {
        switch activeScreen {
        case .timer:
            timerFront
        case .settings:
            appSettingsBack
        case .editTask:
            editTaskBack
        case .library:
            libraryBack
        }
    }

    private func notifyPreferredSizeChange() {
        onPreferredSizeChange?(preferredPanelSize)
    }

    private func navigate(to target: StatusBarTimerScreen, animation: Animation) {
        let source = activeScreen
        guard source != target else { return }

        screenTransitionDirection = target.rawValue < source.rawValue ? .toLeading : .toTrailing
        withAnimation(animation) {
            isShowingTaskLibrary = target == .library
            isShowingSettings = target == .settings
            isShowingTaskEditor = target == .editTask
        }
    }

    private func handleExternalNavigationCommand(_ command: StatusBarNavigationBridge.Command) {
        switch command {
        case .openTimer:
            requestExitFromSettings(to: .timer)
        case .openSettings:
            requestExitFromSettings(to: .settings)
        }
    }

    private func requestExitFromSettings(to target: StatusBarTimerScreen) {
        guard activeScreen == .editTask else {
            navigate(to: target, animation: primaryNavigationAnimation)
            return
        }

        guard hasUnsavedChanges else {
            cancelLiveSuggestion()
            cancelAllSubtaskSuggestions()
            dismissPickers()
            navigate(to: target, animation: primaryNavigationAnimation)
            return
        }

        pendingNavigationTarget = target
        isUnsavedChangesAlertPresented = true
    }

    private func refreshTaskLibrary() {
        userTaskLibraryTemplates = taskLibraryStore
            .load()
            .map { template in
                var copy = template
                copy.source = .user
                return copy
            }
            .sorted(by: { $0.updatedAt > $1.updatedAt })

        premadeTaskLibraryTemplates = premadeTaskCatalog.load()

        let validPremadeIDs = Set(
            premadeTaskLibraryTemplates.compactMap { template in
                template.premadeTemplateID ?? template.id.uuidString
            }
        )
        let savedIDs = taskLibraryStore.loadSavedPremadeTemplateIDs().intersection(validPremadeIDs)
        savedPremadeTemplateIDs = savedIDs
        taskLibraryStore.saveSavedPremadeTemplateIDs(savedIDs)
    }

    private func toggleCurrentFocusFavorite() {
        toggleFavoriteTemplate(viewModel.currentTaskTemplate())
    }

    private func toggleFavoriteTemplate(_ template: TaskTemplate) {
        let signature = template.favoriteSignature

        var templates = taskLibraryStore.load()
        let hasMatchingTemplate = templates.contains { $0.favoriteSignature == signature }
        if !hasMatchingTemplate {
            var templateToSave = template
            let now = Date()
            templateToSave.createdAt = now
            templateToSave.updatedAt = now
            templates.insert(templateToSave, at: 0)
        } else {
            var removedTemplates: [TaskTemplate] = []
            templates.removeAll { existing in
                let shouldRemove = existing.favoriteSignature == signature
                if shouldRemove {
                    removedTemplates.append(existing)
                }
                return shouldRemove
            }

            for removed in removedTemplates {
                if let premadeID = removed.premadeTemplateID {
                    let stillHasCopy = templates.contains { $0.premadeTemplateID == premadeID }
                    if !stillHasCopy {
                        var savedIDs = taskLibraryStore.loadSavedPremadeTemplateIDs()
                        savedIDs.remove(premadeID)
                        taskLibraryStore.saveSavedPremadeTemplateIDs(savedIDs)
                    }
                }
            }
        }

        taskLibraryStore.save(templates)
        refreshTaskLibrary()
    }

    private func togglePremadeFavorite(_ premadeTemplate: TaskTemplate) {
        guard premadeTemplate.source == .premade else { return }
        let premadeID = premadeTemplate.premadeTemplateID ?? premadeTemplate.id.uuidString
        var templates = taskLibraryStore.load()
        var savedIDs = taskLibraryStore.loadSavedPremadeTemplateIDs()

        if savedPremadeTemplateIDs.contains(premadeID) {
            templates.removeAll { $0.premadeTemplateID == premadeID }
            savedIDs.remove(premadeID)
        } else {
            var userCopy = premadeTemplate.asUserCopy()
            userCopy.premadeTemplateID = premadeID
            userCopy.categoryName = userCopy.resolvedCategoryName
            templates.insert(userCopy, at: 0)
            savedIDs.insert(premadeID)
        }

        taskLibraryStore.save(templates)
        taskLibraryStore.saveSavedPremadeTemplateIDs(savedIDs)
        refreshTaskLibrary()
    }

    private func openBlankTaskForEditing() {
        cancelLiveSuggestion()
        cancelAllSubtaskSuggestions()
        dismissPickers()
        isSavingSession = false

        draftTitle = ""
        draftEmoji = FocusSettings.default.sessionEmoji
        draftFocusMinutes = FocusSettings.default.focusMinutes
        draftAccentHex = FocusSettings.default.sessionAccentHex
        draftTasks = []
        draftSubTaskTimersEnabled = false

        isEditingNewTask = true
        navigate(to: .editTask, animation: drawerNavigationAnimation)
    }

    private func loadTaskTemplate(_ template: TaskTemplate) {
        viewModel.applyTaskTemplate(template, startImmediately: false)
        isEditingNewTask = false
        navigate(to: .timer, animation: .easeInOut(duration: 0.2))
    }

    private func startTaskTemplate(_ template: TaskTemplate) {
        viewModel.applyTaskTemplate(template, startImmediately: true)
        isEditingNewTask = false
        navigate(to: .timer, animation: .easeInOut(duration: 0.2))
    }

    private func deleteTaskTemplate(_ template: TaskTemplate) {
        guard template.source == .user else { return }
        var templates = taskLibraryStore.load()
        templates.removeAll(where: { $0.id == template.id })
        taskLibraryStore.save(templates)

        if let premadeID = template.premadeTemplateID {
            let hasOtherSavedCopy = templates.contains { $0.premadeTemplateID == premadeID }
            if !hasOtherSavedCopy {
                var savedIDs = taskLibraryStore.loadSavedPremadeTemplateIDs()
                savedIDs.remove(premadeID)
                taskLibraryStore.saveSavedPremadeTemplateIDs(savedIDs)
            }
        }

        refreshTaskLibrary()
    }

    // MARK: - Layout Subviews

    private var timerFront: some View {
        StatusBarTimerFrontCard(
            viewModel: viewModel,
            theme: theme,
            displayMode: timerFrontDisplayMode,
            displayedRingProgress: displayedRingProgress,
            currentTaskID: currentTaskID,
            emojiBackgroundColor: emojiBackgroundColor,
            onOpenLibrary: {
                dismissPickers()
                navigate(to: .library, animation: drawerNavigationAnimation)
            },
            onOpenSettings: {
                navigate(to: .settings, animation: primaryNavigationAnimation)
            },
            onCreateBlankTask: {
                openBlankTaskForEditing()
            },
            onEditTimer: {
                isEditingNewTask = false
                prepareDrafts()
                navigate(to: .editTask, animation: primaryNavigationAnimation)
            },
            onPreviousMusicTrack: {
                viewModel.previousFocusMusicTrack()
            },
            onSeekBackwardMusic: {
                viewModel.seekFocusMusicBackward(seconds: 10)
            },
            onTogglePlayPauseMusic: {
                viewModel.toggleFocusMusicPlayback()
            },
            onSeekForwardMusic: {
                viewModel.seekFocusMusicForward(seconds: 10)
            },
            onNextMusicTrack: {
                viewModel.nextFocusMusicTrack()
            },
            onOpenMusic: {
                viewModel.openSpotifyPlaylistPreview(viewModel.spotifyPlaylistURIOrURL)
            },
            isFavorite: isCurrentFocusFavorite,
            onToggleFavorite: {
                toggleCurrentFocusFavorite()
            },
            onDisplayModeChange: { mode in
                timerFrontDisplayModeRawValue = mode.rawValue
            }
        )
        .padding(timerFrontDisplayMode == .minified ? 0 : 7)
        .onAppear {
            viewModel.refreshSpotifyPlaylistMetadataIfNeeded()
        }
    }

    private var libraryBack: some View {
        StatusBarTimerLibraryScreen(
            userTemplates: userTaskLibraryTemplates,
            premadeTemplates: premadeTaskLibraryTemplates,
            savedPremadeTemplateIDs: savedPremadeTemplateIDs,
            theme: theme,
            selectedTab: $librarySelectedTab,
            selectedCategoryName: $librarySelectedCategoryName,
            currentPage: $libraryCurrentPage,
            onClose: {
                dismissPickers()
                navigate(to: .timer, animation: drawerNavigationAnimation)
            },
            onLoadTemplate: loadTaskTemplate,
            onStartTemplate: startTaskTemplate,
            onTogglePremadeFavorite: togglePremadeFavorite,
            onDeleteTemplate: deleteTaskTemplate
        )
    }

    private var appSettingsBack: some View {
        StatusBarTimerSettingsScreen(
            viewModel: viewModel,
            aiStatus: aiStatus,
            theme: theme,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: settingsSecondaryTextColor,
            cardBackground: settingsCardBackground,
            pillBackground: settingsPillBackground,
            spotifyPlaylistDraft: $appSettingsSpotifyPlaylistDraft,
            statusMessage: $appSettingsStatusMessage,
            onClose: closeAppSettings
        )
    }

    private var editTaskBack: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusBarTimerEditHeaderSection(
                isSaving: isSavingSession,
                hasUnsavedChanges: hasUnsavedChanges,
                isEditingNewTask: isEditingNewTask,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: settingsSecondaryTextColor,
                accentColor: theme.ringProgressColor,
                colorScheme: colorScheme,
                cardBackground: settingsCardBackground,
                pillBackground: settingsPillBackground,
                emojiBackgroundColor: emojiBackgroundColor,
                draftTitle: $draftTitle,
                draftEmoji: StatusBarTimerDraftHelpers.normalizedEmoji(
                    draftEmoji,
                    fallback: FocusSettings.default.sessionEmoji
                ),
                draftAccentHex: draftAccentHex,
                isLiveSuggesting: isLiveSuggesting,
                draftSubTaskTimersEnabled: draftSubTaskTimersEnabled,
                effectiveDraftFocusMinutes: effectiveDraftFocusMinutes,
                draftFocusMinutes: draftFocusMinutes,
                isEmojiPickerPresented: $isEmojiPickerPresented,
                isDurationPickerPresented: $isDurationPickerPresented,
                onClose: { requestExitFromSettings(to: .timer) },
                onSave: { saveSessionChanges() },
                onTitleChange: applyLiveSuggestion,
                onEmojiTap: {
                    let current = StatusBarTimerDraftHelpers.normalizedEmoji(
                        draftEmoji,
                        fallback: FocusSettings.default.sessionEmoji
                    )
                    emojiGridSelection = .init(emoji: Emoji(current), category: emojiGridCategory)
                    isEmojiPickerPresented.toggle()
                },
                emojiPickerPopover: AnyView(emojiPickerPopover),
                durationPickerPopover: AnyView(durationPickerPopover)
            )
            
            subtasksSection
                .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            clearSubtaskTitleFocus()
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func updateMeasuredContentHeight(_ rawHeight: CGFloat, for measuredView: StatusBarTimerMeasuredView) {
        let normalized = max(1, ceil(rawHeight))
        switch measuredView {
        case .settings:
            guard abs(measuredSettingsContentHeight - normalized) > 0.5 else { return }
            measuredSettingsContentHeight = normalized
        case .editTask:
            guard abs(measuredEditTaskContentHeight - normalized) > 0.5 else { return }
            measuredEditTaskContentHeight = normalized
        case .library:
            guard abs(measuredLibraryContentHeight - normalized) > 0.5 else { return }
            measuredLibraryContentHeight = normalized
        case .timer:
            guard abs(measuredTimerContentHeight - normalized) > 0.5 else { return }
            measuredTimerContentHeight = normalized
        }
    }

    // MARK: - Row Views

    private var subtasksSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sub-tasks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextColor.opacity(0.92))
                Spacer()
                if draftTasks.isEmpty {
                    autoSuggestButton
                } else {
                    clearSubtasksButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)

            VStack(spacing: 8) {
                ForEach(draftTasks) { task in
                    if let taskBinding = bindingForTask(id: task.id) {
                        StatusBarEditableSubtaskRow(
                            task: taskBinding,
                            showsDuration: draftSubTaskTimersEnabled,
                            theme: theme,
                            settingsPillBackground: settingsPillBackground,
                            hoveredTaskID: $hoveredTaskID,
                            focusedSubtaskID: $focusedSubtaskID,
                            editingTaskDurationID: $editingTaskDurationID,
                            onRemove: removeDraftTask,
                            onTitleChange: handleSubtaskTitleChange,
                            onVisualTap: presentSubtaskVisualPicker,
                            durationPopoverBinding: subtaskDurationPopoverBinding(for:),
                            durationPickerContent: subtaskDurationPickerPopover(task:),
                            visualPopoverBinding: subtaskVisualPopoverBinding(for:),
                            visualPickerContent: subtaskVisualPickerPopover(task:)
                        )
                            .onDrag {
                                clearSubtaskTitleFocus()
                                draggedTaskID = task.id
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SubtaskDropDelegate(
                                    targetTaskID: task.id,
                                    tasks: $draftTasks,
                                    draggedTaskID: $draggedTaskID
                                )
                            )
                    }
                }

                Button {
                    addDraftTask()
                } label: {
                    HStack(spacing: 10) {
                        Text("Add task")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1)
                            .foregroundStyle(settingsSecondaryTextColor)
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(settingsSecondaryTextColor)
                            .frame(width: 18, height: 18)
                            .background(settingsPillBackground, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay(
                        RoundedRectangle(cornerRadius: innerCardCornerRadius, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(settingsDividerColor)
                    )
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .onChange(of: draftTasks) { _ in
                if draftSubTaskTimersEnabled, subtaskMinutesTotal > 0 {
                    draftFocusMinutes = subtaskMinutesTotal
                }
            }

            StatusBarDivider(color: settingsDividerColor)

            HStack {
                Text("Timers on sub-tasks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Toggle("", isOn: $draftSubTaskTimersEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.ringProgressColor)
                    .onChange(of: draftSubTaskTimersEnabled) { isEnabled in
                        if isEnabled, subtaskMinutesTotal > 0 {
                            draftFocusMinutes = subtaskMinutesTotal
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(settingsCardBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private var autoSuggestButton: some View {
        StatusBarSubtasksHeaderButton(
            foreground: primaryTextColor.opacity(0.86),
            background: settingsPillBackground,
            colorScheme: colorScheme
        ) {
            autoSuggestSubtasks()
        } label: {
            HStack(spacing: 6) {
                if isAutoSuggestingSubtasks {
                    ProgressView()
                        .controlSize(.small)
                        .tint(primaryTextColor.opacity(0.85))
                }

                Text("Break down")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                            Color(red: 188/255, green: 170/255, blue: 255/255)
                                .opacity(colorScheme == .dark ? 0.68 : 0.82)
                        )
            }
        }
    }

    private var clearSubtasksButton: some View {
        StatusBarSubtasksHeaderButton(
            foreground: primaryTextColor.opacity(0.86),
            background: settingsPillBackground,
            colorScheme: colorScheme
        ) {
            clearDraftTasks()
        } label: {
            HStack(spacing: 6) {
                Text("Clear")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var durationPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus duration")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsSecondaryTextColor)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(StatusBarTimerDraftHelpers.durationOptions(maxMinutes: 180), id: \.self) { minutes in
                        durationOptionRow(
                            title: StatusBarTimerDraftHelpers.formattedDuration(minutes),
                            selected: draftFocusMinutes == minutes
                        ) {
                            draftFocusMinutes = minutes
                            isDurationPickerPresented = false
                        }
                    }
                }
            }
            .frame(height: 210)
        }
        .padding(11)
        .frame(width: 198)
    }

    private func prepareDrafts() {
        cancelLiveSuggestion()
        cancelAllSubtaskSuggestions()
        dismissPickers()
        draftTitle = viewModel.sessionTitle
        draftEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(viewModel.sessionEmoji, fallback: FocusSettings.default.sessionEmoji)
        draftFocusMinutes = max(1, Int(viewModel.focusMinutes.rounded()))
        draftAccentHex = HexColor.normalize(viewModel.sessionAccentHex) ?? FocusSettings.default.sessionAccentHex
        draftTasks = viewModel.tasks.isEmpty ? FocusSettings.default.subTasks : viewModel.tasks
        draftSubTaskTimersEnabled = viewModel.subTaskTimersEnabled
        viewModel.clearFocusMusicStatusMessage()
        if draftSubTaskTimersEnabled, subtaskMinutesTotal > 0 {
            draftFocusMinutes = subtaskMinutesTotal
        }
    }

    // MARK: - Draft Actions

    private func saveSessionChanges(afterSaveScreen: StatusBarTimerScreen = .timer) {
        cancelLiveSuggestion()
        cancelAllSubtaskSuggestions()
        dismissPickers()
        isSavingSession = true
        Task {
            viewModel.updateSessionTitle(draftTitle)
            viewModel.updateSessionEmoji(StatusBarTimerDraftHelpers.normalizedEmoji(draftEmoji, fallback: FocusSettings.default.sessionEmoji))
            viewModel.updateFocusMinutes(Double(effectiveDraftFocusMinutes))
            viewModel.updateSessionAccentHex(normalizedDraftAccentHex)
            viewModel.updateTasks(StatusBarTimerDraftHelpers.normalizedTasks(draftTasks))
            viewModel.updateSubTaskTimersEnabled(draftSubTaskTimersEnabled)

            await MainActor.run {
                prepareDrafts()
                isSavingSession = false
                isEditingNewTask = false
                navigate(to: afterSaveScreen, animation: primaryNavigationAnimation)
            }
        }
    }

    private func closeAppSettings() {
        guard viewModel.focusMusicEnabled else {
            appSettingsSpotifyPlaylistDraft = viewModel.spotifyPlaylistURIOrURL
            appSettingsStatusMessage = nil
            navigate(to: .timer, animation: primaryNavigationAnimation)
            return
        }

        let trimmed = appSettingsSpotifyPlaylistDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.updateSpotifyPlaylistURIOrURL(trimmed) {
            viewModel.syncSpotifyPreviewToSavedPlaylistIfNeeded()
            appSettingsSpotifyPlaylistDraft = viewModel.spotifyPlaylistURIOrURL
            appSettingsStatusMessage = nil
            navigate(to: .timer, animation: primaryNavigationAnimation)
        } else {
            appSettingsStatusMessage = viewModel.focusMusicStatusMessage
        }
    }

    private func applyLiveSuggestion(from title: String) {
        cancelLiveSuggestion()

        let baselineEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(draftEmoji, fallback: FocusSettings.default.sessionEmoji)
        let baselineMinutes = draftFocusMinutes
        let baselineAccent = normalizedDraftAccentHex

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let letterCount = trimmedTitle.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= liveSuggestionMinimumLetterCount else { return }

        isLiveSuggesting = true
        let requestToken = suggestionGate.beginRequest(for: .live)
        let task = Task {
            try? await Task.sleep(nanoseconds: liveSuggestionDebounceNanoseconds)
            guard !Task.isCancelled, suggestionGate.isCurrent(requestToken, for: .live) else { return }

            let base = SessionSetupSuggestion(
                title: trimmedTitle,
                emoji: baselineEmoji,
                focusMinutes: baselineMinutes,
                accentHex: baselineAccent
            )
            let refinedSuggestion = await viewModel.suggestSessionSetup(prompt: trimmedTitle, current: base)
            guard !Task.isCancelled, suggestionGate.isCurrent(requestToken, for: .live) else { return }

            await MainActor.run {
                guard suggestionGate.isCurrent(requestToken, for: .live) else { return }

                if draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTitle,
                   let refinedSuggestion
                {
                    applySuggestionToDrafts(refinedSuggestion)
                }
                suggestionGate.completeRequest(requestToken, for: .live)
                suggestionTaskBag.remove(.live)
                isLiveSuggesting = false
            }
        }
        suggestionTaskBag.replace(task, for: .live)
    }

    private func applySuggestionToDrafts(_ suggestion: SessionSetupSuggestion) {
        draftEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(suggestion.emoji, fallback: FocusSettings.default.sessionEmoji)
        draftFocusMinutes = min(180, max(1, suggestion.focusMinutes))
        draftAccentHex = HexColor.normalize(suggestion.accentHex) ?? normalizedDraftAccentHex
    }

    private func cancelLiveSuggestion() {
        suggestionGate.invalidate(.live)
        suggestionTaskBag.cancel(.live)
        isLiveSuggesting = false
    }

    private func dismissPickers() {
        clearSubtaskTitleFocus()
        isEmojiPickerPresented = false
        isDurationPickerPresented = false
        editingTaskDurationID = nil
        editingTaskVisualID = nil
    }

    private func clearSubtaskTitleFocus() {
        focusedSubtaskID = nil
    }

    private func addDraftTask() {
        clearSubtaskTitleFocus()
        draftTasks.append(
            FocusTask(
                emoji: FocusTask.defaultEmoji,
                title: "New sub-task",
                durationMinutes: 5,
                accentHex: FocusTask.defaultAccentHex,
                isDone: false
            )
        )
        if draftSubTaskTimersEnabled, subtaskMinutesTotal > 0 {
            draftFocusMinutes = subtaskMinutesTotal
        }
    }

    private func removeDraftTask(id: UUID) {
        cancelSubtaskSuggestion(for: id)
        if focusedSubtaskID == id {
            focusedSubtaskID = nil
        }
        if editingTaskDurationID == id {
            editingTaskDurationID = nil
        }
        if editingTaskVisualID == id {
            editingTaskVisualID = nil
        }
        if hoveredTaskID == id {
            hoveredTaskID = nil
        }
        if draggedTaskID == id {
            draggedTaskID = nil
        }
        draftTasks.removeAll { $0.id == id }
        if draftSubTaskTimersEnabled, subtaskMinutesTotal > 0 {
            draftFocusMinutes = subtaskMinutesTotal
        }
    }

    private func clearDraftTasks() {
        clearSubtaskTitleFocus()
        cancelAllSubtaskSuggestions()
        editingTaskDurationID = nil
        editingTaskVisualID = nil
        hoveredTaskID = nil
        draggedTaskID = nil
        draftTasks = []
        draftSubTaskTimersEnabled = false
    }

    private func handleSubtaskTitleChange(taskID: UUID, title: String) {
        applySubtaskLiveSuggestion(for: taskID, title: title)
    }

    private func presentSubtaskVisualPicker(taskID: UUID) {
        guard let task = draftTasks.first(where: { $0.id == taskID }) else { return }
        let currentEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(task.emoji, fallback: FocusTask.defaultEmoji)
        subtaskEmojiGridSelection = .init(emoji: Emoji(currentEmoji), category: subtaskEmojiGridCategory)
        editingTaskVisualID = taskID
    }

    private func applySubtaskLiveSuggestion(for taskID: UUID, title: String) {
        cancelSubtaskSuggestion(for: taskID)

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let letterCount = trimmedTitle.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= subtaskLiveSuggestionMinimumLetterCount else { return }

        guard let task = draftTasks.first(where: { $0.id == taskID }) else { return }

        let baseline = SessionSetupSuggestion(
            title: trimmedTitle,
            emoji: StatusBarTimerDraftHelpers.normalizedEmoji(task.emoji, fallback: FocusTask.defaultEmoji),
            focusMinutes: max(1, task.durationMinutes),
            accentHex: HexColor.normalize(task.accentHex) ?? FocusSettings.default.sessionAccentHex
        )
        let key: SuggestionTaskBag.Key = .subtask(taskID)
        let requestToken = suggestionGate.beginRequest(for: key)

        let suggestionTask = Task {
            try? await Task.sleep(nanoseconds: subtaskLiveSuggestionDebounceNanoseconds)
            guard !Task.isCancelled, suggestionGate.isCurrent(requestToken, for: key) else { return }

            let refinedSuggestion = await viewModel.suggestSessionSetup(prompt: trimmedTitle, current: baseline)
            guard !Task.isCancelled, suggestionGate.isCurrent(requestToken, for: key) else { return }

            await MainActor.run {
                guard suggestionGate.isCurrent(requestToken, for: key) else { return }
                defer {
                    suggestionGate.completeRequest(requestToken, for: key)
                    suggestionTaskBag.remove(key)
                }

                guard let refinedSuggestion else { return }
                guard let index = draftTasks.firstIndex(where: { $0.id == taskID }) else { return }
                guard draftTasks[index].title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTitle else { return }

                let suggestedEmoji = StatusBarTimerDraftHelpers.normalizedEmoji(refinedSuggestion.emoji, fallback: draftTasks[index].emoji)
                draftTasks[index].emoji = suggestedEmoji

                let clampedDuration = min(120, max(1, refinedSuggestion.focusMinutes))
                let steppedDuration = min(120, max(5, Int((Double(clampedDuration) / 5.0).rounded()) * 5))
                draftTasks[index].durationMinutes = steppedDuration
            }
        }

        suggestionTaskBag.replace(suggestionTask, for: key)
    }

    private func cancelSubtaskSuggestion(for taskID: UUID) {
        let key: SuggestionTaskBag.Key = .subtask(taskID)
        suggestionGate.invalidate(key)
        suggestionTaskBag.cancel(key)
    }

    private func cancelAllSubtaskSuggestions() {
        for taskID in suggestionTaskBag.subtaskTaskIDs {
            cancelSubtaskSuggestion(for: taskID)
        }
    }

    private func cancelSuggestionTasksForDeletedSubtasks(currentTaskIDs: Set<UUID>) {
        for taskID in suggestionTaskBag.subtaskTaskIDs where !currentTaskIDs.contains(taskID) {
            cancelSubtaskSuggestion(for: taskID)
        }
    }

    private func autoSuggestSubtasks() {
        guard !isAutoSuggestingSubtasks else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isAutoSuggestingSubtasks = true
        Task {
            let suggested = await viewModel.suggestSubtasks(
                title: title,
                totalMinutes: draftFocusMinutes,
                current: StatusBarTimerDraftHelpers.normalizedTasks(draftTasks)
            )

            await MainActor.run {
                if let suggested, !suggested.isEmpty {
                    cancelAllSubtaskSuggestions()
                    draftTasks = StatusBarTimerDraftHelpers.normalizedTasks(suggested)
                    draftSubTaskTimersEnabled = true
                    if subtaskMinutesTotal > 0 {
                        draftFocusMinutes = subtaskMinutesTotal
                    }
                }
                isAutoSuggestingSubtasks = false
            }
        }
    }

    private func bindingForTask(id: UUID) -> Binding<FocusTask>? {
        guard let index = draftTasks.firstIndex(where: { $0.id == id }) else { return nil }
        return $draftTasks[index]
    }

    // MARK: - Pickers

    private func subtaskDurationPopoverBinding(for taskID: UUID) -> Binding<Bool> {
        Binding(
            get: { editingTaskDurationID == taskID },
            set: { isPresented in
                if !isPresented, editingTaskDurationID == taskID {
                    editingTaskDurationID = nil
                }
            }
        )
    }

    private func subtaskVisualPopoverBinding(for taskID: UUID) -> Binding<Bool> {
        Binding(
            get: { editingTaskVisualID == taskID },
            set: { isPresented in
                if !isPresented, editingTaskVisualID == taskID {
                    editingTaskVisualID = nil
                }
            }
        )
    }

    private func subtaskDurationPickerPopover(task: Binding<FocusTask>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sub-task duration")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsSecondaryTextColor)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(StatusBarTimerDraftHelpers.durationOptions(maxMinutes: 120), id: \.self) { minutes in
                        durationOptionRow(
                            title: StatusBarTimerDraftHelpers.formattedDuration(minutes),
                            selected: task.wrappedValue.durationMinutes == minutes
                        ) {
                            task.wrappedValue.durationMinutes = minutes
                            editingTaskDurationID = nil
                        }
                    }
                }
            }
            .frame(height: 210)
        }
        .padding(11)
        .frame(width: 198)
    }

    private func subtaskVisualPickerPopover(task: Binding<FocusTask>) -> some View {
        StatusBarEmojiColorPickerPopover(
            emoji: task.emoji,
            accentHex: task.accentHex,
            emojiCategory: $subtaskEmojiGridCategory,
            emojiSelection: $subtaskEmojiGridSelection,
            fallbackColor: Color(hex: draftAccentHex) ?? emojiBackgroundColor,
            categoryColorHexes: categoryColorHexes,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: settingsSecondaryTextColor,
            dividerColor: settingsDividerColor
        )
    }

    private func durationOptionRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(primaryTextColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect()
    }

    // MARK: - Reusable UI Helpers

    private var emojiPickerPopover: some View {
        StatusBarEmojiColorPickerPopover(
            emoji: $draftEmoji,
            accentHex: $draftAccentHex,
            emojiCategory: $emojiGridCategory,
            emojiSelection: $emojiGridSelection,
            fallbackColor: emojiBackgroundColor,
            categoryColorHexes: categoryColorHexes,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: settingsSecondaryTextColor,
            dividerColor: settingsDividerColor
        )
    }
}
