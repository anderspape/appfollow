import SwiftUI

struct StatusBarTimerFrontCard: View {
    @ObservedObject var viewModel: TimerViewModel
    let theme: StatusBarTimerTheme
    let displayMode: TimerFrontDisplayMode
    let displayedRingProgress: Double
    let currentTaskID: UUID?
    let emojiBackgroundColor: Color
    let onOpenLibrary: () -> Void
    let onOpenToday: () -> Void
    let onOpenSettings: () -> Void
    let onCreateBlankTask: () -> Void
    let onEditTimer: () -> Void
    let onPreviousMusicTrack: () -> Void
    let onSeekBackwardMusic: () -> Void
    let onTogglePlayPauseMusic: () -> Void
    let onSeekForwardMusic: () -> Void
    let onNextMusicTrack: () -> Void
    let onOpenMusic: () -> Void
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onDisplayModeChange: (TimerFrontDisplayMode) -> Void

    @State private var taskConfettiTrigger = 0
    @State private var isShowingTaskConfetti = false
    @State private var isFocusMusicPlayerExpanded = false
    @State private var isShowingCompactCompletionFeedback = false

    private var playerBleedInset: CGFloat { theme.panelInnerPadding + 7 }

    private var ringLineWidth: CGFloat { 18 }
    private var ringSize: CGFloat { 120.4 }
    private var centerSize: CGFloat { ringSize - ringLineWidth + 3 }
    private var emojiSize: CGFloat { 50 }
    private var showsMainTaskAboveSubtaskTitle: Bool {
        viewModel.subTaskTimersEnabled
            && !viewModel.tasks.isEmpty
            && viewModel.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && viewModel.sessionTitle != viewModel.timerDisplayTitle
    }

    private var timerToggleSymbolName: String {
        viewModel.shouldShowResetCTA ? "arrow.counterclockwise" : (viewModel.isRunning ? "pause.fill" : "play.fill")
    }

    var body: some View {
        Group {
            if displayMode == .minified {
                minifiedContent
            } else {
                fullContent
            }
        }
        .overlay(alignment: .center) {
            if isShowingTaskConfetti {
                StatusBarTaskConfettiOverlay(trigger: taskConfettiTrigger) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isShowingTaskConfetti = false
                    }
                }
                .frame(width: displayMode == .minified ? 340 : 220, height: displayMode == .minified ? 180 : 220)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isShowingTaskConfetti)
        .animation(.easeInOut(duration: 0.22), value: isFocusMusicPlayerExpanded)
        .onChange(of: displayMode) { mode in
            if mode == .minified {
                isFocusMusicPlayerExpanded = false
            }
        }
        .onChange(of: viewModel.focusMusicEnabled) { isEnabled in
            guard !isEnabled else { return }
            isFocusMusicPlayerExpanded = false
        }
        .onChange(of: viewModel.completedTaskEventCounter) { _ in
            isShowingTaskConfetti = true
            taskConfettiTrigger += 1
            TaskCompletionSoundPlayer.shared.play()
        }
    }

    private var minifiedContent: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                    onDisplayModeChange(.full)
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(theme.ringTrackColor, lineWidth: 5)

                        Circle()
                            .trim(from: 0, to: displayedRingProgress)
                            .stroke(
                                theme.ringProgressColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.25), value: displayedRingProgress)

                        Circle()
                            .fill(emojiBackgroundColor)
                            .frame(width: 28, height: 28)
                            .frame(width: 28, height: 28)

                        Text(viewModel.timerDisplayEmoji)
                            .font(.system(size: 12))
                    }
                    .frame(width: 33, height: 33)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.timerDisplayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primaryTextColor.opacity(0.96))
                            .lineLimit(1)
                        Text(viewModel.timeText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.secondaryTextColor.opacity(0.95))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .statusBarHoverEffect()

            if let currentTaskID {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isShowingCompactCompletionFeedback = true
                    }
                    viewModel.toggleTask(id: currentTaskID)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        withAnimation(.easeOut(duration: 0.14)) {
                            isShowingCompactCompletionFeedback = false
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 28, height: 28)

                        Circle()
                            .stroke(theme.primaryTextColor, lineWidth: 1.6)
                            .frame(width: 18, height: 18)

                        if isShowingCompactCompletionFeedback {
                            Circle()
                                .fill(theme.primaryTextColor)
                                .frame(width: 18, height: 18)
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(theme.colorScheme == .dark ? Color.black : Color.white)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect()
            }

            Button {
                if viewModel.shouldShowResetCTA {
                    viewModel.resetCompletedSubtasksAndStart()
                } else {
                    viewModel.toggleTimer()
                }
            } label: {
                Image(systemName: timerToggleSymbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.primaryTextColor.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(theme.settingsPillBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                .fill(theme.taskCardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                        .stroke(theme.taskCardStrokeColor, lineWidth: 0.8)
                )
        )
    }

    private var fullContent: some View {
        VStack(spacing: 0) {
            headerToolbar
                .padding(.bottom, 10)

            titleSection
                .padding(.top, showsMainTaskAboveSubtaskTitle ? 10 : 0)
                .padding(.bottom, isFocusMusicPlayerExpanded ? 18 : 30)

            if viewModel.focusMusicEnabled && isFocusMusicPlayerExpanded {
                expandedFocusMusicSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        )
                    )
            } else {
                timerCoreSection

                if !viewModel.tasks.isEmpty {
                    taskListSection
                }

                if viewModel.focusMusicEnabled {
                    compactFocusMusicSection
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            )
                        )
                }
            }
        }
    }

    private var headerToolbar: some View {
        HStack {
            HStack(spacing: 8) {
                StatusBarToolbarButton(
                    systemName: "magnifyingglass",
                    tint: theme.primaryTextColor,
                    action: onOpenLibrary
                )
                StatusBarToolbarButton(
                    systemName: "arrow.up.right.and.arrow.down.left",
                    tint: theme.primaryTextColor
                ) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                        onDisplayModeChange(.minified)
                    }
                }
                StatusBarToolbarButton(
                    systemName: isFavorite ? "heart.fill" : "heart",
                    tint: isFavorite ? theme.favoriteAccentColor : theme.primaryTextColor,
                    action: onToggleFavorite
                )
            }
            Spacer()
            HStack(spacing: 8) {
                StatusBarAccentToolbarButton(
                    systemName: "plus",
                    accentColor: theme.ringProgressColor,
                    colorScheme: theme.colorScheme,
                    action: onCreateBlankTask
                )
            }
        }
    }

    private var titleSection: some View {
        Group {
            if showsMainTaskAboveSubtaskTitle {
                VStack(spacing: 6) {
                    Text(viewModel.sessionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryTextColor.opacity(0.75))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    Text(viewModel.timerDisplayTitle)
                        .font(.custom("Recoleta-Regular", size: 21))
                        .foregroundStyle(theme.primaryTextColor)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text(viewModel.timerDisplayTitle)
                    .font(.custom("Recoleta-Regular", size: 21))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

            }
        }
    }

    private var timerCoreSection: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(emojiBackgroundColor)
                    .frame(width: centerSize, height: centerSize)

                Circle()
                    .stroke(theme.ringTrackColor, lineWidth: ringLineWidth)

                Circle()
                    .trim(from: 0, to: displayedRingProgress)
                    .stroke(
                        theme.ringProgressColor,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: displayedRingProgress)

                Text(viewModel.timerDisplayEmoji)
                    .font(.system(size: emojiSize))
            }
            .frame(width: ringSize, height: ringSize)
            .contentShape(Circle())
            .onTapGesture {
                onEditTimer()
            }
            .padding(.bottom, 20)

            Button(action: onEditTimer) {
                Text(viewModel.timeText)
                    .font(.custom("Recoleta-Regular", size: 27))
                    .foregroundStyle(theme.primaryTextColor)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect()
            .padding(.bottom, 12)

            HStack(spacing: 14) {
                Button("+1") {
                    viewModel.addMinute()
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect()
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryTextColor)
                .frame(minWidth: 44, minHeight: 40)
                .contentShape(Rectangle())

                Button {
                    if viewModel.shouldShowResetCTA {
                        viewModel.resetCompletedSubtasksAndStart()
                    } else {
                        viewModel.toggleTimer()
                    }
                } label: {
                    ZStack {
                        Capsule()
                            .fill(theme.playPauseBackgroundColor)
                            .frame(width: 74, height: 42)
                        Image(systemName: timerToggleSymbolName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect()
            }
            .padding(.bottom, 14)
        }
    }

    private var taskListSection: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.tasks) { task in
                StatusBarFocusTaskRow(
                    task: task,
                    isCurrent: currentTaskID == task.id,
                    showDuration: viewModel.subTaskTimersEnabled,
                    theme: theme
                ) {
                    viewModel.toggleTask(id: task.id)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var compactFocusMusicSection: some View {
        focusMusicCard(isExpanded: false)
            .padding(.horizontal, -playerBleedInset)
            .padding(.bottom, -playerBleedInset)
    }

    private var expandedFocusMusicSection: some View {
        focusMusicCard(isExpanded: true)
            .padding(.horizontal, -playerBleedInset)
            .padding(.bottom, -playerBleedInset)
    }

    private func focusMusicCard(isExpanded: Bool) -> some View {
        StatusBarFocusMusicPlayerCard(
            theme: theme,
            isEnabled: viewModel.focusMusicEnabled,
            isPlaying: viewModel.isFocusMusicPlaying,
            isExpanded: isExpanded,
            isFallbackActive: viewModel.isFallbackMusicActive,
            primaryLabel: viewModel.spotifyPlaybackPrimaryLabel,
            secondaryLabel: viewModel.spotifyPlaybackSecondaryLabel,
            coverURL: viewModel.spotifyPlaybackCoverURL,
            playbackProgress: viewModel.spotifyPlaybackProgress,
            elapsedLabel: viewModel.spotifyPlaybackElapsedLabel,
            durationLabel: viewModel.spotifyPlaybackDurationLabel,
            isMetadataLoading: viewModel.isSpotifyPlaylistMetadataLoading,
            onPrevious: onPreviousMusicTrack,
            onSeekBackward: onSeekBackwardMusic,
            onTogglePlayback: onTogglePlayPauseMusic,
            onSeekForward: onSeekForwardMusic,
            onNext: onNextMusicTrack,
            onOpen: onOpenMusic,
            onToggleExpanded: toggleFocusMusicExpansion
        )
    }

    private func toggleFocusMusicExpansion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isFocusMusicPlayerExpanded.toggle()
        }
    }

}

private struct StatusBarFocusTaskRow: View {
    let task: FocusTask
    let isCurrent: Bool
    let showDuration: Bool
    let theme: StatusBarTimerTheme
    let onTap: () -> Void

    var body: some View {
        let title = isCurrent ? "Now: \(task.title)" : task.title

        return Button(action: onTap) {
            HStack(spacing: 10) {
                Text(task.emoji)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .background(
                        Circle()
                            .fill(Color(hex: task.accentHex) ?? Color(red: 0.93, green: 0.92, blue: 0.99))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryTextColor.opacity(task.isDone ? 0.62 : 0.96))
                        .strikethrough(task.isDone, color: theme.secondaryTextColor)
                        .lineLimit(1)

                    if showDuration {
                        Text("\(max(1, task.durationMinutes))m")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.secondaryTextColor)
                    }
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .stroke(theme.primaryTextColor, lineWidth: 1.6)

                    if task.isDone {
                        Circle()
                            .fill(theme.primaryTextColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.colorScheme == .dark ? Color.black : Color.white)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, showDuration ? 6 : 7)
            .background(
                RoundedRectangle(cornerRadius: theme.innerCardCornerRadius, style: .continuous)
                    .fill(theme.taskCardFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.innerCardCornerRadius, style: .continuous)
                            .stroke(theme.taskCardStrokeColor, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect()
    }
}
