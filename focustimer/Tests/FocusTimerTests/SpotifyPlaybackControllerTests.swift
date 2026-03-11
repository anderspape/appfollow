import XCTest
@testable import FocusTimer

final class SpotifyPlaybackControllerTests: XCTestCase {
    func testNormalizedPlaylistURIAcceptsSpotifyURI() {
        let input = "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        XCTAssertEqual(
            SpotifyPlaybackController.normalizedPlaylistURI(from: input),
            input
        )
    }

    func testNormalizedPlaylistURIAcceptsOpenSpotifyURL() {
        let input = "https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6?si=abc"
        XCTAssertEqual(
            SpotifyPlaybackController.normalizedPlaylistURI(from: input),
            "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"
        )
    }

    func testNormalizedPlaylistURIRejectsInvalidInput() {
        XCTAssertNil(SpotifyPlaybackController.normalizedPlaylistURI(from: ""))
        XCTAssertNil(SpotifyPlaybackController.normalizedPlaylistURI(from: "https://example.com"))
        XCTAssertNil(SpotifyPlaybackController.normalizedPlaylistURI(from: "spotify:artist:123"))
    }
}
