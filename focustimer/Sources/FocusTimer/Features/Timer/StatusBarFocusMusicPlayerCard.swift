import SwiftUI
import AppKit
import CoreImage

struct StatusBarFocusMusicPlayerCard: View {
    let theme: StatusBarTimerTheme
    let isEnabled: Bool
    let isPlaying: Bool
    let isExpanded: Bool
    let isFallbackActive: Bool
    let primaryLabel: String
    let secondaryLabel: String
    let coverURL: URL?
    let playbackProgress: Double
    let elapsedLabel: String
    let durationLabel: String
    let isMetadataLoading: Bool
    let onPrevious: () -> Void
    let onSeekBackward: () -> Void
    let onTogglePlayback: () -> Void
    let onSeekForward: () -> Void
    let onNext: () -> Void
    let onOpen: () -> Void
    let onToggleExpanded: () -> Void

    @State private var artworkGlowColor: Color = Color(red: 0.21, green: 0.74, blue: 0.44)
    private let spotifyGreen = Color(red: 29 / 255, green: 185 / 255, blue: 84 / 255)
    private var equalizerTint: Color {
        artworkGlowColor.opacity(isEnabled ? 0.95 : 0.52)
    }
    private var displayedPrimaryLabel: String {
        primaryLabel.isEmpty ? "Focus Playlist" : primaryLabel
    }
    private var displayedSecondaryLabel: String {
        secondaryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var normalizedPlaybackProgress: Double {
        min(max(playbackProgress, 0), 1)
    }
    private var compactCardHorizontalPadding: CGFloat { 12 }
    private var compactCardVerticalPadding: CGFloat { 12 }
    private var expandedCardHorizontalPadding: CGFloat { 18 }
    private var expandedCardVerticalPadding: CGFloat { 20 }
    private var artworkColorSourceID: String {
        if let coverURL {
            return coverURL.absoluteString
        }
        if playlistCoverImage != nil {
            return "playlist-fallback"
        }
        return "gradient-fallback"
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedCard
            } else {
                compactCard
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .task(id: artworkColorSourceID) {
            await resolveArtworkGlowColor()
        }
    }

    private var compactCard: some View {
        cardSurface {
            compactContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpanded()
        }
    }

    private var expandedCard: some View {
        cardSurface {
            expandedContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func cardSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
        let horizontalPadding: CGFloat = isExpanded ? expandedCardHorizontalPadding : compactCardHorizontalPadding
        let verticalPadding: CGFloat = isExpanded ? expandedCardVerticalPadding : compactCardVerticalPadding
        return content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                ZStack {
                    shape.fill(theme.taskCardFillColor.opacity(theme.colorScheme == .dark ? 0.86 : 0.9))
                    shape.fill(
                        LinearGradient(
                            colors: [
                                artworkGlowColor.opacity(isExpanded ? 0.2 : 0.14),
                                artworkGlowColor.opacity(isExpanded ? 0.08 : 0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    shape.fill(
                        RadialGradient(
                            colors: [
                                artworkGlowColor.opacity(isExpanded ? 0.2 : 0.16),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 6,
                            endRadius: isExpanded ? 260 : 170
                        )
                    )
                }
            )
            .overlay(
                shape
                    .stroke(Color.white.opacity(theme.colorScheme == .dark ? 0.12 : 0.18), lineWidth: 0.7)
            )
            .clipShape(shape)
            .contentShape(shape)
    }

    private var compactContent: some View {
        HStack(alignment: .center, spacing: 12) {
            coverArt
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    StatusBarMusicPulseIndicator(
                        isActive: isEnabled && isPlaying,
                        tint: equalizerTint
                    )
                    .frame(width: 12, height: 12)

                    StatusBarMarqueeText(
                        text: displayedPrimaryLabel,
                        font: .system(size: 14, weight: .semibold),
                        color: theme.primaryTextColor.opacity(isEnabled ? 0.96 : 0.6),
                        speed: 22,
                        gap: 28
                    )
                }
                .frame(height: 18)

                if !displayedSecondaryLabel.isEmpty {
                    Text(displayedSecondaryLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryTextColor.opacity(isEnabled ? 0.95 : 0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            controlButton(systemName: isPlaying ? "pause.fill" : "play.fill", action: onTogglePlayback)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                if !isFallbackActive {
                    Button(action: onOpen) {
                        spotifyLogoIcon
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .statusBarHoverEffect(enabled: isEnabled)
                    .disabled(!isEnabled)
                }

                Spacer(minLength: 8)

                Button(action: onToggleExpanded) {
                    topBarIconLabel(
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.primaryTextColor.opacity(0.92))
                    )
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect(enabled: true)
            }
            .padding(.top, 2)

            expandedArtworkShowcase
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    StatusBarMusicPulseIndicator(
                        isActive: isEnabled && isPlaying,
                        tint: equalizerTint
                    )
                    .frame(width: 14, height: 14)

                    StatusBarMarqueeText(
                        text: displayedPrimaryLabel,
                        font: .system(size: 20, weight: .semibold),
                        color: theme.primaryTextColor.opacity(isEnabled ? 0.96 : 0.6),
                        speed: 24,
                        gap: 32
                    )
                }
                .frame(height: 24)

                if !displayedSecondaryLabel.isEmpty {
                    Text(displayedSecondaryLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryTextColor.opacity(isEnabled ? 0.95 : 0.6))
                        .lineLimit(1)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                StatusBarPlayerProgressRow(
                    progress: normalizedPlaybackProgress,
                    elapsedLabel: elapsedLabel,
                    durationLabel: durationLabel,
                    tint: theme.primaryTextColor.opacity(0.95),
                    trackTint: theme.primaryTextColor.opacity(theme.colorScheme == .dark ? 0.32 : 0.24)
                )
                .padding(.vertical, 8)

                HStack(spacing: 22) {
                    transportButton(systemName: "gobackward.10", action: onSeekBackward)
                    transportButton(systemName: "arrow.left.to.line", action: onPrevious)
                    transportButton(
                        systemName: isPlaying ? "pause.fill" : "play.fill",
                        isPrimary: true,
                        action: onTogglePlayback
                    )
                    transportButton(systemName: "arrow.right.to.line", action: onNext)
                    transportButton(systemName: "goforward.10", action: onSeekForward)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var expandedArtworkShowcase: some View {
        GeometryReader { proxy in
            ZStack {
                expandedArtworkBlurBand(in: proxy.size)

                Circle()
                    .fill(artworkGlowColor.opacity(isEnabled ? 0.38 : 0.2))
                    .frame(width: 228, height: 228)
                    .blur(radius: 42)

                Circle()
                    .fill(artworkGlowColor.opacity(isEnabled ? 0.44 : 0.25))
                    .frame(width: 172, height: 172)
                    .blur(radius: 14)

                coverArt
                    .frame(width: 176, height: 176)
                    .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 248)
        .allowsHitTesting(false)
    }

    private func expandedArtworkBlurBand(in size: CGSize) -> some View {
        coverArt
            .frame(
                width: size.width + (expandedCardHorizontalPadding * 2) + 220,
                height: size.height + 36
            )
            .clipped()
            .saturation(1.08)
            .contrast(1.02)
            .compositingGroup()
            .blur(radius: 36, opaque: true)
            .opacity(theme.colorScheme == .dark ? 0.23 : 0.29)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.95), location: 0.22),
                                .init(color: .white.opacity(0.95), location: 0.78),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .position(x: size.width / 2, y: size.height / 2)
    }

    private var coverArt: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        loadingCover
                    case .failure:
                        fallbackCover
                    @unknown default:
                        fallbackCover
                    }
                }
            } else if let image = playlistCoverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackCover
            }
        }
    }

    private var loadingCover: some View {
        fallbackCover.overlay {
            if isMetadataLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.9))
            }
        }
    }

    private var fallbackCover: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.16, blue: 0.18),
                        spotifyGreen.opacity(0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Group {
                    if isFallbackActive {
                        fallbackModeIcon
                    } else {
                        spotifyLogoIcon
                    }
                }
                .frame(width: 24, height: 24)
                .opacity(0.95)
            )
    }

    private var fallbackModeIcon: some View {
        Image(systemName: "waveform")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.primaryTextColor)
    }

    private var playlistCoverImage: NSImage? {
        let candidates: [(String, String?)] = [
            ("focus-playlist-cover", "png"),
            ("focus-playlist-cover", "jpg")
        ]

        for (name, ext) in candidates {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Brand/Spotify"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private var spotifyLogoIcon: some View {
        Group {
            if let spotifyLogoImage {
                Image(nsImage: spotifyLogoImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
    }

    private var spotifyLogoImage: NSImage? {
        if let url = Bundle.module.url(
            forResource: "Primary_Logo_Green_RGB",
            withExtension: "pdf"
        ) {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.module.url(
            forResource: "Primary_Logo_Green_RGB",
            withExtension: "pdf",
            subdirectory: "Brand/Spotify"
        ) {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.module.url(
            forResource: "Spotify_Primary_Logo_RGB_Green",
            withExtension: "png"
        ) {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    @ViewBuilder
    private func transportButton(
        systemName: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isPrimary {
                    Circle()
                        .fill(theme.primaryTextColor.opacity(theme.colorScheme == .dark ? 0.95 : 0.9))
                        .frame(width: 52, height: 52)
                }
                Image(systemName: systemName)
                    .font(.system(size: isPrimary ? 18 : 16, weight: .semibold))
                    .foregroundStyle(
                        isPrimary
                            ? (theme.colorScheme == .dark ? Color.black.opacity(0.92) : Color.white.opacity(0.96))
                            : theme.primaryTextColor.opacity(isEnabled ? 0.94 : 0.55)
                    )
                    .frame(width: isPrimary ? 52 : 32, height: isPrimary ? 52 : 32)
            }
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect(enabled: isEnabled)
        .disabled(!isEnabled)
    }

    private func resolveArtworkGlowColor() async {
        if let coverURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: coverURL)
                if Task.isCancelled { return }
                if let image = NSImage(data: data),
                   let extracted = Self.glowColor(from: image)
                {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            artworkGlowColor = extracted
                        }
                    }
                    return
                }
            } catch {
                // Keep fallback color.
            }
        }

        if let playlistCoverImage,
           let extracted = Self.glowColor(from: playlistCoverImage)
        {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) {
                    artworkGlowColor = extracted
                }
            }
            return
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) {
                artworkGlowColor = spotifyGreen
            }
        }
    }

    private static func glowColor(from image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff)
        else {
            return nil
        }

        let extent = ciImage.extent
        guard !extent.isEmpty,
              let averageFilter = CIFilter(name: "CIAreaAverage")
        else {
            return nil
        }
        averageFilter.setValue(ciImage, forKey: kCIInputImageKey)
        averageFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let outputImage = averageFilter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let red = Double(bitmap[0]) / 255.0
        let green = Double(bitmap[1]) / 255.0
        let blue = Double(bitmap[2]) / 255.0
        let alpha = Double(bitmap[3]) / 255.0
        guard alpha > 0.01 else { return nil }

        let nsColor = NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1
        )
        let hsb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var opacity: CGFloat = 1
        hsb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)

        let boostedSaturation = min(1, max(0.25, saturation * 1.32))
        let boostedBrightness = min(1, max(0.44, brightness * 1.05))
        let toned = NSColor(
            calibratedHue: hue,
            saturation: boostedSaturation,
            brightness: boostedBrightness,
            alpha: 1
        )
        return Color(nsColor: toned)
    }

    private func controlButton(
        systemName: String,
        allowWhenDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.primaryTextColor.opacity((isEnabled || allowWhenDisabled) ? 0.9 : 0.55))
                .frame(width: 30, height: 30)
                .background(theme.settingsPillBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect(enabled: isEnabled || allowWhenDisabled)
        .disabled(!isEnabled && !allowWhenDisabled)
    }

    private func topBarIconLabel<Icon: View>(_ icon: Icon) -> some View {
        icon
            .frame(width: 32, height: 32)
            .background(theme.settingsPillBackground, in: Circle())
    }
}

private struct StatusBarPlayerProgressRow: View {
    let progress: Double
    let elapsedLabel: String
    let durationLabel: String
    let tint: Color
    let trackTint: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(elapsedLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .monospacedDigit()
                .frame(width: 34, height: 7, alignment: .center)

            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let progressWidth = width * clampedProgress
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackTint)
                    Capsule()
                        .fill(tint)
                        .frame(width: progressWidth)
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .offset(x: max(0, progressWidth - 3.5))
                        .shadow(color: tint.opacity(0.4), radius: 1.5, y: 0.5)
                }
            }
            .frame(height: 2)

            Text(durationLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .monospacedDigit()
                .frame(width: 34, alignment: .center)
        }
    }
}

private struct StatusBarMusicPulseIndicator: View {
    let isActive: Bool
    let tint: Color

    var body: some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                bars(date: timeline.date)
            }
        } else {
            bars(date: nil)
        }
    }

    private func bars(date: Date?) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(tint)
                    .frame(width: 2.4, height: barHeight(at: index, date: date))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func barHeight(at index: Int, date: Date?) -> CGFloat {
        guard let date else {
            return [3.6, 6.2, 4.6][index]
        }

        let time = date.timeIntervalSinceReferenceDate
        let seed = Double(index) * 1.618
        let fast = sin(time * 8.1 + seed * 2.4)
        let medium = sin(time * 4.6 + seed * 0.7)
        let slow = sin(time * 2.3 + seed * 3.2)
        let jitter = sin(time * 13.0 + seed * 1.9)
        let mix = fast * 0.44 + medium * 0.29 + slow * 0.2 + jitter * 0.07
        let normalized = max(0, min(1, (mix + 1) * 0.5))
        return 3.2 + CGFloat(normalized * 7.6)
    }
}

private struct StatusBarMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: CGFloat
    let gap: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var scrollStartDate = Date()

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width)
            let shouldScroll = textWidth > availableWidth + 2
            let loopDistance = max(0, textWidth + gap)

            ZStack(alignment: .leading) {
                if shouldScroll, loopDistance > 1 {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        HStack(spacing: gap) {
                            baseLabel
                            baseLabel
                        }
                        .offset(x: marqueeOffset(distance: loopDistance, at: timeline.date))
                    }
                } else {
                    baseLabel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .overlay(alignment: .leading) {
                baseLabel
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textProxy in
                            Color.clear
                                .onAppear {
                                    updateMeasuredTextWidth(textProxy.size.width)
                                }
                                .onChange(of: textProxy.size.width) {
                                    updateMeasuredTextWidth($0)
                                }
                        }
                    )
                    .hidden()
            }
        }
        .onAppear {
            scrollStartDate = Date()
        }
        .onChange(of: text) { _ in
            scrollStartDate = Date()
            textWidth = 0
        }
    }

    private var baseLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func updateMeasuredTextWidth(_ width: CGFloat) {
        let normalized = max(0, ceil(width))
        guard abs(normalized - textWidth) > 0.5 else { return }
        textWidth = normalized
        scrollStartDate = Date()
    }

    private func marqueeOffset(distance: CGFloat, at date: Date) -> CGFloat {
        let clampedDistance = max(0, distance)
        guard clampedDistance > 0.5 else { return 0 }

        let cycleDuration = max(2.0, Double(clampedDistance / max(1, speed)))
        let elapsed = max(0, date.timeIntervalSince(scrollStartDate))
        let progress = CGFloat((elapsed / cycleDuration).truncatingRemainder(dividingBy: 1))
        return -clampedDistance * progress
    }
}
