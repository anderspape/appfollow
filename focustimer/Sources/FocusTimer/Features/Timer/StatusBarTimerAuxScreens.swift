import SwiftUI

struct StatusBarTimerLibraryScreen: View {
    let userTemplates: [TaskTemplate]
    let premadeTemplates: [TaskTemplate]
    let savedPremadeTemplateIDs: Set<String>
    let theme: StatusBarTimerTheme
    @Binding var selectedTab: StatusBarTaskLibraryDrawer.TaskLibraryTab
    @Binding var selectedCategoryName: String?
    @Binding var currentPage: Int
    let onClose: () -> Void
    let onLoadTemplate: (TaskTemplate) -> Void
    let onStartTemplate: (TaskTemplate) -> Void
    let onTogglePremadeFavorite: (TaskTemplate) -> Void
    let onDeleteTemplate: (TaskTemplate) -> Void

    var body: some View {
        StatusBarTaskLibraryDrawer(
            userTemplates: userTemplates,
            premadeTemplates: premadeTemplates,
            savedPremadeTemplateIDs: savedPremadeTemplateIDs,
            theme: theme,
            isEmbedded: true,
            onClose: onClose,
            onLoadTemplate: onLoadTemplate,
            onStartTemplate: onStartTemplate,
            onTogglePremadeFavorite: onTogglePremadeFavorite,
            onDeleteTemplate: onDeleteTemplate,
            selectedTab: $selectedTab,
            selectedCategoryName: $selectedCategoryName,
            currentPage: $currentPage
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct StatusBarTimerSettingsScreen: View {
    @ObservedObject var viewModel: TimerViewModel
    let aiStatus: SessionSetupAIStatus
    let theme: StatusBarTimerTheme
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let cardBackground: Color
    let pillBackground: Color
    @Binding var spotifyPlaylistDraft: String
    @Binding var statusMessage: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusBarSimpleHeader(
                title: "Settings",
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor
            ) {
                onClose()
            }

            sectionLabel("Focus music")
            StatusBarFocusMusicSettingsCard(
                isEnabled: viewModel.focusMusicEnabled,
                selectedProvider: viewModel.focusMusicProvider,
                playlistText: spotifyPlaylistDraft,
                savedPlaylistText: viewModel.spotifyPlaylistURIOrURL,
                statusMessage: statusMessage ?? viewModel.focusMusicStatusMessage,
                fallbackChannels: viewModel.fallbackChannels,
                defaultFallbackChannelID: viewModel.defaultFallbackChannelID,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                cardBackground: cardBackground,
                pillBackground: pillBackground,
                accentColor: theme.ringProgressColor
            ) { isEnabled in
                viewModel.updateFocusMusicEnabled(isEnabled)
                statusMessage = nil
            } onProviderChange: { provider in
                viewModel.updateFocusMusicProvider(provider)
                statusMessage = nil
            } onPlaylistChange: { newValue in
                spotifyPlaylistDraft = newValue
                statusMessage = nil
                viewModel.clearFocusMusicStatusMessage()
            } onFallbackChannelChange: { selectedID in
                viewModel.updateDefaultFallbackChannelID(selectedID)
                statusMessage = nil
            } onSaveSpotifyPlaylist: {
                let trimmed = spotifyPlaylistDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if viewModel.updateSpotifyPlaylistURIOrURL(trimmed) {
                    viewModel.syncSpotifyPreviewToSavedPlaylistIfNeeded()
                    statusMessage = nil
                } else {
                    statusMessage = viewModel.focusMusicStatusMessage
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("AI support")
                StatusBarAISettingsCard(
                    isEnabled: viewModel.aiEnabled,
                    status: aiStatus,
                    primaryTextColor: primaryTextColor,
                    secondaryTextColor: secondaryTextColor,
                    cardBackground: cardBackground,
                    accentColor: theme.ringProgressColor
                ) { isEnabled in
                    viewModel.updateAIEnabled(isEnabled)
                }
            }
        }
        .onAppear {
            spotifyPlaylistDraft = viewModel.spotifyPlaylistURIOrURL
            statusMessage = nil
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(secondaryTextColor.opacity(0.8))
            .tracking(0.6)
            .padding(.horizontal, 2)
    }
}

struct StatusBarTimerEditHeaderSection: View {
    let isSaving: Bool
    let hasUnsavedChanges: Bool
    let isEditingNewTask: Bool
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let accentColor: Color
    let colorScheme: ColorScheme
    let cardBackground: Color
    let pillBackground: Color
    let emojiBackgroundColor: Color
    @Binding var draftTitle: String
    let draftEmoji: String
    let draftAccentHex: String
    let isLiveSuggesting: Bool
    let draftSubTaskTimersEnabled: Bool
    let effectiveDraftFocusMinutes: Int
    let draftFocusMinutes: Int
    @Binding var isEmojiPickerPresented: Bool
    @Binding var isDurationPickerPresented: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    let onTitleChange: (String) -> Void
    let onEmojiTap: () -> Void
    let emojiPickerPopover: AnyView
    let durationPickerPopover: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusBarSettingsHeader(
                isSaving: isSaving,
                hasUnsavedChanges: hasUnsavedChanges,
                title: isEditingNewTask ? "New task" : "Edit Task",
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                accentColor: accentColor,
                colorScheme: colorScheme
            ) {
                onClose()
            } onSave: {
                onSave()
            }

            VStack(alignment: .leading, spacing: 12) {
                StatusBarSessionIdentityCard(
                    title: $draftTitle,
                    placeholder: isEditingNewTask ? "" : "Add title",
                    primaryTextColor: primaryTextColor,
                    cardBackground: cardBackground,
                    isLiveSuggesting: isLiveSuggesting,
                    emoji: draftEmoji,
                    emojiBackgroundColor: Color(hex: draftAccentHex) ?? emojiBackgroundColor,
                    isEmojiPickerPresented: $isEmojiPickerPresented
                ) { newValue in
                    onTitleChange(newValue)
                } onEmojiTap: {
                    onEmojiTap()
                } emojiPickerPopover: {
                    emojiPickerPopover
                }

                StatusBarDurationColorCard(
                    primaryTextColor: primaryTextColor,
                    cardBackground: cardBackground,
                    pillBackground: pillBackground,
                    isSubTaskTimersEnabled: draftSubTaskTimersEnabled,
                    effectiveMinutesText: StatusBarTimerDraftHelpers.formattedDuration(effectiveDraftFocusMinutes),
                    focusMinutesText: StatusBarTimerDraftHelpers.formattedDuration(draftFocusMinutes),
                    isDurationPickerPresented: $isDurationPickerPresented
                ) {
                    durationPickerPopover
                }
            }
        }
    }
}
