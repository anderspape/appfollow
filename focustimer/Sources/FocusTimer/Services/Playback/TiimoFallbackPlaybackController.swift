import Foundation
import AVFoundation

final class TiimoFallbackPlaybackController: FallbackFocusMusicControlling {
    private let channelsProvider: TiimoMusicChannelsProviding
    private var player: AVPlayer?
    private var currentChannelIndex: Int?
    private var volumeLevel: Float = 1

    private(set) var channelsSnapshot: [TiimoMusicChannel] = []
    private(set) var localizedListenersText: String?
    private(set) var isMuted = false
    var defaultFallbackChannelID: String?

    init(channelsProvider: TiimoMusicChannelsProviding = TiimoMusicChannelsService()) {
        self.channelsProvider = channelsProvider
    }

    func prefetchChannels() async {
        _ = await ensureChannelsLoaded(force: false)
    }

    func play(playlist _: String?) async -> FocusMusicControlResult {
        if let result = await ensureChannelsLoaded(force: false) {
            return result
        }

        if currentChannelIndex == nil {
            let startIndex = preferredStartIndex()
            setCurrentChannel(at: startIndex, autoplay: true)
            return .success
        }

        if player == nil {
            setCurrentChannel(at: preferredStartIndex(), autoplay: true)
            return .success
        }

        player?.play()
        return .success
    }

    func pause() async -> FocusMusicControlResult {
        player?.pause()
        return .success
    }

    func next() async -> FocusMusicControlResult {
        if let result = await ensureChannelsLoaded(force: false) {
            return result
        }

        guard !channelsSnapshot.isEmpty else {
            return .commandFailed("No fallback channels available.")
        }

        let current = currentChannelIndex ?? preferredStartIndex()
        let nextIndex = (current + 1) % channelsSnapshot.count
        setCurrentChannel(at: nextIndex, autoplay: true)
        return .success
    }

    func previous() async -> FocusMusicControlResult {
        if let result = await ensureChannelsLoaded(force: false) {
            return result
        }

        guard !channelsSnapshot.isEmpty else {
            return .commandFailed("No fallback channels available.")
        }

        let current = currentChannelIndex ?? preferredStartIndex()
        let previousIndex = (current - 1 + channelsSnapshot.count) % channelsSnapshot.count
        setCurrentChannel(at: previousIndex, autoplay: true)
        return .success
    }

    func seek(by seconds: Int) async -> FocusMusicControlResult {
        guard let player else { return .commandFailed("Fallback player is not active.") }

        let current = player.currentTime().seconds
        let safeCurrent = current.isFinite ? current : 0
        let duration = player.currentItem?.duration.seconds ?? .nan
        let safeDuration: Double = {
            guard duration.isFinite, duration > 0 else { return .greatestFiniteMagnitude }
            return duration
        }()

        let target = min(max(0, safeCurrent + Double(seconds)), safeDuration)
        await player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        return .success
    }

    func adjustVolume(by delta: Int) async -> FocusMusicControlResult {
        let currentPercent = Int((volumeLevel * 100).rounded())
        let nextPercent = min(100, max(0, currentPercent + delta))
        volumeLevel = Float(nextPercent) / 100
        player?.volume = volumeLevel
        return .success
    }

    func setMuted(_ muted: Bool) async -> FocusMusicControlResult {
        isMuted = muted
        player?.isMuted = muted
        return .success
    }

    func openInSpotify(playlist _: String?) async -> FocusMusicControlResult {
        .commandFailed("Unavailable in fallback mode.")
    }

    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? {
        guard let currentChannel = currentChannel else { return nil }

        let position = player?.currentTime().seconds
        let duration = player?.currentItem?.duration.seconds

        let safePosition: Double? = {
            guard let position, position.isFinite, position >= 0 else { return nil }
            return position
        }()

        let safeDuration: Double? = {
            guard let duration, duration.isFinite, duration > 0 else { return nil }
            return duration
        }()

        return FocusMusicPlaybackSnapshot(
            isPlaying: player?.timeControlStatus == .playing,
            isMuted: player?.isMuted ?? isMuted,
            trackTitle: currentChannel.name,
            artistName: nil,
            albumTitle: "Tiimo Music",
            artworkURL: currentChannel.coverURL,
            playbackPositionSeconds: safePosition,
            trackDurationSeconds: safeDuration
        )
    }

    private var currentChannel: TiimoMusicChannel? {
        guard let currentChannelIndex,
              channelsSnapshot.indices.contains(currentChannelIndex)
        else {
            return nil
        }
        return channelsSnapshot[currentChannelIndex]
    }

    private func preferredStartIndex() -> Int {
        if let defaultFallbackChannelID,
           let index = channelsSnapshot.firstIndex(where: { $0.id == defaultFallbackChannelID })
        {
            return index
        }
        if let lofiIndex = channelsSnapshot.firstIndex(where: { Self.isLofiChannelName($0.name) }) {
            return lofiIndex
        }
        if let currentChannelIndex,
           channelsSnapshot.indices.contains(currentChannelIndex)
        {
            return currentChannelIndex
        }
        return 0
    }

    private func setCurrentChannel(at index: Int, autoplay: Bool) {
        guard channelsSnapshot.indices.contains(index) else { return }
        currentChannelIndex = index
        let channel = channelsSnapshot[index]
        let item = AVPlayerItem(url: channel.fileURL)

        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
            player?.volume = volumeLevel
        }

        player?.isMuted = isMuted
        if autoplay {
            player?.play()
        }
    }

    private func ensureChannelsLoaded(force: Bool) async -> FocusMusicControlResult? {
        if !force, !channelsSnapshot.isEmpty {
            return nil
        }

        let locale = Locale.preferredLanguages.first
        let result = await channelsProvider.fetchChannels(locale: locale)
        switch result {
        case .success(let payload):
            channelsSnapshot = payload.channels
            localizedListenersText = payload.localizedListenersText
            if channelsSnapshot.isEmpty {
                return .commandFailed("No fallback channels available.")
            }
            if let defaultFallbackChannelID,
               !channelsSnapshot.contains(where: { $0.id == defaultFallbackChannelID })
            {
                self.defaultFallbackChannelID = nil
            }
            if defaultFallbackChannelID == nil,
               let suggested = channelsSnapshot.first(where: { Self.isLofiChannelName($0.name) })?.id
            {
                defaultFallbackChannelID = suggested
            }
            return nil
        case .failure(let error):
            let message: String
            switch error {
            case .invalidResponse:
                message = "invalid response"
            case .decoding:
                message = "invalid data"
            case .network:
                message = "network error"
            case .emptyChannels:
                message = "no channels"
            }
            return .commandFailed("Tiimo fallback unavailable (\(message)).")
        }
    }

    private static func isLofiChannelName(_ name: String) -> Bool {
        let normalized = name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return normalized.contains("lofi")
    }
}
