import Foundation
import AppKit

protocol FallbackFocusMusicControlling: AnyObject, FocusMusicControlling {
    var channelsSnapshot: [TiimoMusicChannel] { get }
    var defaultFallbackChannelID: String? { get set }
    func prefetchChannels() async
}

protocol HybridFocusMusicStateProviding: AnyObject {
    var isUsingFallbackMusic: Bool { get }
    var fallbackChannels: [TiimoMusicChannel] { get }
    var defaultFallbackMusicChannelID: String? { get }
    var canSwitchBackToSpotifyNow: Bool { get }
    var preferredProvider: FocusMusicProvider { get }
    var activeProvider: FocusMusicProvider { get }

    func setDefaultFallbackMusicChannelID(_ id: String?)
    func setPreferredProvider(_ provider: FocusMusicProvider)
    func pauseAllProvidersForSwitch() async
    func refreshFallbackChannels() async
    func switchBackToSpotifyIfAvailable() async -> Bool
}

final class HybridFocusMusicController: FocusMusicControlling, HybridFocusMusicStateProviding {
    private enum ActiveMode {
        case spotify
        case tiimoFallback
    }

    private let spotifyController: FocusMusicControlling
    private let fallbackController: FallbackFocusMusicControlling
    private let spotifyAvailability: () -> Bool
    private var activeMode: ActiveMode = .spotify
    private(set) var preferredProvider: FocusMusicProvider = .spotify

    private(set) var canSwitchBackToSpotifyNow = false

    init(
        spotifyController: FocusMusicControlling = SpotifyPlaybackController(),
        fallbackController: FallbackFocusMusicControlling = TiimoFallbackPlaybackController(),
        spotifyAvailability: @escaping () -> Bool = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        }
    ) {
        self.spotifyController = spotifyController
        self.fallbackController = fallbackController
        self.spotifyAvailability = spotifyAvailability
    }

    var isUsingFallbackMusic: Bool {
        activeMode == .tiimoFallback
    }

    var fallbackChannels: [TiimoMusicChannel] {
        fallbackController.channelsSnapshot
    }

    var defaultFallbackMusicChannelID: String? {
        fallbackController.defaultFallbackChannelID
    }

    var activeProvider: FocusMusicProvider {
        switch activeMode {
        case .spotify:
            return .spotify
        case .tiimoFallback:
            return .tiimoRadio
        }
    }

    func setDefaultFallbackMusicChannelID(_ id: String?) {
        fallbackController.defaultFallbackChannelID = id
    }

    func setPreferredProvider(_ provider: FocusMusicProvider) {
        preferredProvider = provider
        switch provider {
        case .spotify:
            activeMode = .spotify
        case .tiimoRadio:
            activeMode = .tiimoFallback
            canSwitchBackToSpotifyNow = false
        }
    }

    func pauseAllProvidersForSwitch() async {
        _ = await spotifyController.pause()
        _ = await fallbackController.pause()
    }

    func refreshFallbackChannels() async {
        await fallbackController.prefetchChannels()
    }

    func switchBackToSpotifyIfAvailable() async -> Bool {
        guard spotifyAvailability() else { return false }
        _ = await fallbackController.pause()
        preferredProvider = .spotify
        activeMode = .spotify
        canSwitchBackToSpotifyNow = false
        return true
    }

    func play(playlist: String?) async -> FocusMusicControlResult {
        if preferredProvider == .tiimoRadio {
            activeMode = .tiimoFallback
            canSwitchBackToSpotifyNow = false
            return await fallbackController.play(playlist: nil)
        }

        if activeMode == .tiimoFallback {
            if spotifyAvailability() {
                canSwitchBackToSpotifyNow = true
            }
            return await fallbackController.play(playlist: nil)
        }

        let spotifyResult = await spotifyController.play(playlist: playlist)
        switch spotifyResult {
        case .success:
            canSwitchBackToSpotifyNow = false
            return .success
        case .appNotInstalled:
            let fallbackResult = await fallbackController.play(playlist: nil)
            if fallbackResult == .success {
                activeMode = .tiimoFallback
                canSwitchBackToSpotifyNow = false
            }
            return fallbackResult
        case .permissionDenied, .invalidPlaylist, .commandFailed:
            return spotifyResult
        }
    }

    func pause() async -> FocusMusicControlResult {
        switch activeMode {
        case .spotify:
            return await spotifyController.pause()
        case .tiimoFallback:
            return await fallbackController.pause()
        }
    }

    func next() async -> FocusMusicControlResult {
        switch activeMode {
        case .spotify:
            return await spotifyController.next()
        case .tiimoFallback:
            return await fallbackController.next()
        }
    }

    func previous() async -> FocusMusicControlResult {
        switch activeMode {
        case .spotify:
            return await spotifyController.previous()
        case .tiimoFallback:
            return await fallbackController.previous()
        }
    }

    func seek(by seconds: Int) async -> FocusMusicControlResult {
        switch activeMode {
        case .spotify:
            return await spotifyController.seek(by: seconds)
        case .tiimoFallback:
            return await fallbackController.seek(by: seconds)
        }
    }

    func adjustVolume(by delta: Int) async -> FocusMusicControlResult {
        switch activeMode {
        case .spotify:
            return await spotifyController.adjustVolume(by: delta)
        case .tiimoFallback:
            return await fallbackController.adjustVolume(by: delta)
        }
    }

    func setMuted(_ muted: Bool) async -> FocusMusicControlResult {
        switch activeMode {
        case .spotify:
            return await spotifyController.setMuted(muted)
        case .tiimoFallback:
            return await fallbackController.setMuted(muted)
        }
    }

    func openInSpotify(playlist: String?) async -> FocusMusicControlResult {
        guard activeMode == .spotify else {
            return .commandFailed("Unavailable in fallback mode.")
        }
        return await spotifyController.openInSpotify(playlist: playlist)
    }

    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? {
        switch activeMode {
        case .spotify:
            return await spotifyController.playbackSnapshot()
        case .tiimoFallback:
            if spotifyAvailability() {
                canSwitchBackToSpotifyNow = true
            }
            return await fallbackController.playbackSnapshot()
        }
    }
}
