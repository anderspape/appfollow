import XCTest
@testable import FocusTimer

@MainActor
final class HybridFocusMusicControllerTests: XCTestCase {
    func testSpotifySuccessKeepsSpotifyMode() async {
        let spotify = StubController()
        spotify.playResult = .success
        let fallback = StubFallbackController()
        let controller = HybridFocusMusicController(
            spotifyController: spotify,
            fallbackController: fallback,
            spotifyAvailability: { false }
        )

        let result = await controller.play(playlist: "spotify:playlist:abc")

        XCTAssertEqual(result, .success)
        XCTAssertFalse(controller.isUsingFallbackMusic)
        XCTAssertEqual(spotify.playInvocations, ["spotify:playlist:abc"])
        XCTAssertTrue(fallback.playInvocations.isEmpty)
    }

    func testAppNotInstalledActivatesFallback() async {
        let spotify = StubController()
        spotify.playResult = .appNotInstalled
        let fallback = StubFallbackController()
        fallback.playResult = .success
        let controller = HybridFocusMusicController(
            spotifyController: spotify,
            fallbackController: fallback,
            spotifyAvailability: { false }
        )

        let result = await controller.play(playlist: "spotify:playlist:abc")

        XCTAssertEqual(result, .success)
        XCTAssertTrue(controller.isUsingFallbackMusic)
        XCTAssertEqual(spotify.playInvocations.count, 1)
        XCTAssertEqual(fallback.playInvocations.count, 1)
    }

    func testPermissionDeniedDoesNotActivateFallback() async {
        let spotify = StubController()
        spotify.playResult = .permissionDenied
        let fallback = StubFallbackController()
        let controller = HybridFocusMusicController(
            spotifyController: spotify,
            fallbackController: fallback,
            spotifyAvailability: { false }
        )

        let result = await controller.play(playlist: "spotify:playlist:abc")

        XCTAssertEqual(result, .permissionDenied)
        XCTAssertFalse(controller.isUsingFallbackMusic)
        XCTAssertTrue(fallback.playInvocations.isEmpty)
    }

    func testNextPreviousUseFallbackWhenFallbackIsActive() async {
        let spotify = StubController()
        spotify.playResult = .appNotInstalled
        let fallback = StubFallbackController()
        fallback.playResult = .success
        let controller = HybridFocusMusicController(
            spotifyController: spotify,
            fallbackController: fallback,
            spotifyAvailability: { false }
        )

        _ = await controller.play(playlist: "spotify:playlist:abc")
        _ = await controller.next()
        _ = await controller.previous()

        XCTAssertEqual(fallback.nextInvocationCount, 1)
        XCTAssertEqual(fallback.previousInvocationCount, 1)
    }

    func testFallbackPlaySetsSwitchBackSuggestionWhenSpotifyReturns() async {
        let spotify = StubController()
        spotify.playResult = .appNotInstalled
        let fallback = StubFallbackController()
        fallback.playResult = .success
        var spotifyInstalled = false
        let controller = HybridFocusMusicController(
            spotifyController: spotify,
            fallbackController: fallback,
            spotifyAvailability: { spotifyInstalled }
        )

        _ = await controller.play(playlist: "spotify:playlist:abc")
        XCTAssertFalse(controller.canSwitchBackToSpotifyNow)

        spotifyInstalled = true
        _ = await controller.play(playlist: "spotify:playlist:abc")

        XCTAssertTrue(controller.canSwitchBackToSpotifyNow)
    }
}

private final class StubController: FocusMusicControlling {
    var playResult: FocusMusicControlResult = .success
    var pauseResult: FocusMusicControlResult = .success
    var nextResult: FocusMusicControlResult = .success
    var previousResult: FocusMusicControlResult = .success
    var seekResult: FocusMusicControlResult = .success
    var adjustVolumeResult: FocusMusicControlResult = .success
    var setMutedResult: FocusMusicControlResult = .success
    var openResult: FocusMusicControlResult = .success

    var playInvocations: [String?] = []

    func play(playlist: String?) async -> FocusMusicControlResult {
        playInvocations.append(playlist)
        return playResult
    }

    func pause() async -> FocusMusicControlResult { pauseResult }
    func next() async -> FocusMusicControlResult { nextResult }
    func previous() async -> FocusMusicControlResult { previousResult }
    func seek(by seconds: Int) async -> FocusMusicControlResult { seekResult }
    func adjustVolume(by delta: Int) async -> FocusMusicControlResult { adjustVolumeResult }
    func setMuted(_ muted: Bool) async -> FocusMusicControlResult { setMutedResult }
    func openInSpotify(playlist: String?) async -> FocusMusicControlResult { openResult }
    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? { nil }
}

private final class StubFallbackController: FallbackFocusMusicControlling {
    var playResult: FocusMusicControlResult = .success
    var channelsSnapshot: [TiimoMusicChannel] = []
    var defaultFallbackChannelID: String?

    var playInvocations: [String?] = []
    var nextInvocationCount = 0
    var previousInvocationCount = 0

    func prefetchChannels() async {}

    func play(playlist: String?) async -> FocusMusicControlResult {
        playInvocations.append(playlist)
        return playResult
    }

    func pause() async -> FocusMusicControlResult { .success }

    func next() async -> FocusMusicControlResult {
        nextInvocationCount += 1
        return .success
    }

    func previous() async -> FocusMusicControlResult {
        previousInvocationCount += 1
        return .success
    }

    func seek(by seconds: Int) async -> FocusMusicControlResult { .success }
    func adjustVolume(by delta: Int) async -> FocusMusicControlResult { .success }
    func setMuted(_ muted: Bool) async -> FocusMusicControlResult { .success }
    func openInSpotify(playlist: String?) async -> FocusMusicControlResult { .commandFailed("Unavailable") }
    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? { nil }
}
