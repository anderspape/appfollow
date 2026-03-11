import SwiftUI

struct StatusBarSimpleHeader: View {
    let title: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(secondaryTextColor)

            HStack {
                StatusBarToolbarButton(systemName: "arrow.left", tint: primaryTextColor, action: onBack)
                Spacer()
            }
        }
    }
}

struct StatusBarSettingsHeader: View {
    let isSaving: Bool
    let hasUnsavedChanges: Bool
    let title: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let accentColor: Color
    let colorScheme: ColorScheme
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(secondaryTextColor)

            HStack {
                StatusBarToolbarButton(systemName: "arrow.left", tint: primaryTextColor, action: onBack)

                Spacer()

                StatusBarSaveToolbarButton(
                    isSaving: isSaving,
                    accentColor: accentColor,
                    colorScheme: colorScheme,
                    action: onSave
                )
                .disabled(isSaving || !hasUnsavedChanges)
            }
        }
    }
}

struct StatusBarFocusMusicSettingsCard: View {
    let isEnabled: Bool
    let selectedProvider: FocusMusicProvider
    let playlistText: String
    let savedPlaylistText: String
    let statusMessage: String?
    let fallbackChannels: [TiimoMusicChannel]
    let defaultFallbackChannelID: String?
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let cardBackground: Color
    let pillBackground: Color
    let accentColor: Color
    let onToggle: (Bool) -> Void
    let onProviderChange: (FocusMusicProvider) -> Void
    let onPlaylistChange: (String) -> Void
    let onFallbackChannelChange: (String?) -> Void
    let onSaveSpotifyPlaylist: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4){
                    Text("Focus music")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text("Add calm background music to help you stay with your task.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(secondaryTextColor.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { isEnabled }, set: onToggle))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if isEnabled {
                StatusBarDivider(color: secondaryTextColor.opacity(0.18))

                VStack(alignment: .leading, spacing: 14) {
                    settingsSection(title: "Music source") {
                        Menu {
                            ForEach(FocusMusicProvider.allCases, id: \.self) { provider in
                                Button(providerPickerLabel(for: provider)) {
                                    onProviderChange(provider)
                                }
                            }
                        } label: {
                            HStack {
                                Text(providerPickerLabel(for: selectedProvider))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(primaryTextColor.opacity(0.95))
                                Spacer(minLength: 6)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(secondaryTextColor.opacity(0.85))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(pillBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .statusBarHoverEffect(enabled: true)
                    }

                    if selectedProvider == .spotify {
                        settingsSection(title: "Default playlist") {
                            TextField(
                                "spotify:playlist:...",
                                text: Binding(get: { playlistText }, set: onPlaylistChange)
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(primaryTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(pillBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            HStack(spacing: 8) {
                                Button(action: onSaveSpotifyPlaylist) {
                                    Text("Gem")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(primaryTextColor.opacity(isPlaylistDirty ? 0.95 : 0.6))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(pillBackground, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .statusBarHoverEffect(enabled: isPlaylistDirty)
                                .disabled(!isPlaylistDirty)
                            }
                        }
                    }

                    if selectedProvider == .tiimoRadio {
                        settingsSection(title: "Tiimo Radio") {
                            Menu {
                                Button("Auto (Lo-Fi)") {
                                    onFallbackChannelChange(nil)
                                }
                                ForEach(fallbackChannels) { channel in
                                    Button(channel.name) {
                                        onFallbackChannelChange(channel.id)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedFallbackChannelLabel)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(primaryTextColor.opacity(0.95))
                                    Spacer(minLength: 6)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(secondaryTextColor.opacity(0.85))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(pillBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .statusBarHoverEffect(enabled: true)
                        }
                    }

                    if let statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.orange.opacity(0.95))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
            content()
        }
    }

    private var isPlaylistDirty: Bool {
        normalizePlaylistText(playlistText) != normalizePlaylistText(savedPlaylistText)
    }

    private var selectedFallbackChannelLabel: String {
        if let defaultFallbackChannelID,
           let channel = fallbackChannels.first(where: { $0.id == defaultFallbackChannelID })
        {
            return channel.name
        }
        if fallbackChannels.isEmpty {
            return "Loading channels..."
        }
        if let lofi = fallbackChannels.first(where: { isLofiName($0.name) }) {
            return "Auto (\(lofi.name))"
        }
        return "Auto (\(fallbackChannels[0].name))"
    }

    private func normalizePlaylistText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLofiName(_ value: String) -> Bool {
        value.lowercased().contains("lo-fi") || value.lowercased().contains("lofi")
    }

    private func providerPickerLabel(for provider: FocusMusicProvider) -> String {
        switch provider {
        case .spotify:
            return "Spotify"
        case .tiimoRadio:
            return "Tiimo Radio"
        }
    }
}

struct StatusBarAISettingsCard: View {
    let isEnabled: Bool
    let status: SessionSetupAIStatus
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let cardBackground: Color
    let accentColor: Color
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI support")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text("Get help with task titles, emojis, and sub-tasks.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(secondaryTextColor.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Toggle("", isOn: Binding(get: { isEnabled }, set: onToggle))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            StatusBarDivider(color: secondaryTextColor.opacity(0.18))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.isAvailable ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(status.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryTextColor.opacity(0.84))
                    Spacer(minLength: 0)
                }
                Text(status.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatusBarSessionIdentityCard<EmojiPickerPopover: View>: View {
    @Binding var title: String
    let placeholder: String
    let primaryTextColor: Color
    let cardBackground: Color
    let isLiveSuggesting: Bool
    let emoji: String
    let emojiBackgroundColor: Color
    @Binding var isEmojiPickerPresented: Bool
    let onTitleChange: (String) -> Void
    let onEmojiTap: () -> Void
    @ViewBuilder let emojiPickerPopover: EmojiPickerPopover

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.custom("Recoleta-Regular", size: 16))
                .foregroundStyle(primaryTextColor)
                .onChange(of: title, perform: onTitleChange)

            if isLiveSuggesting {
                ProgressView()
                    .controlSize(.small)
                    .tint(primaryTextColor.opacity(0.85))
            }

            Button(action: onEmojiTap) {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 33)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(emojiBackgroundColor)
                    )
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect()
            .contentShape(Circle())
            .popover(isPresented: $isEmojiPickerPresented, arrowEdge: .top) {
                emojiPickerPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatusBarDurationColorCard<DurationPopover: View>: View {
    let primaryTextColor: Color
    let cardBackground: Color
    let pillBackground: Color
    let isSubTaskTimersEnabled: Bool
    let effectiveMinutesText: String
    let focusMinutesText: String
    @Binding var isDurationPickerPresented: Bool
    @ViewBuilder let durationPopover: DurationPopover

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSettingsRow(label: "Duration", labelColor: primaryTextColor) {
                if isSubTaskTimersEnabled {
                    StatusBarValuePill(backgroundColor: pillBackground) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(effectiveMinutesText)
                        }
                        .foregroundStyle(primaryTextColor.opacity(0.5))
                    }
                } else {
                    Button {
                        isDurationPickerPresented.toggle()
                    } label: {
                        StatusBarValuePill(backgroundColor: pillBackground) {
                            Text(focusMinutesText)
                                .foregroundStyle(primaryTextColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .statusBarHoverEffect()
                    .popover(isPresented: $isDurationPickerPresented, arrowEdge: .top) {
                        durationPopover
                    }
                }
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
