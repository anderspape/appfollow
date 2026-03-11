import XCTest
@testable import FocusTimer

final class SpotifyPlaylistMetadataServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolStub.handler = nil
        URLProtocolStub.requestCount = 0
    }

    func testSpotifyURIProducesOEmbedRequest() async {
        let session = makeStubSession(statusCode: 200, body: """
        {"title":"Deep Focus","type":"playlist","thumbnail_url":"https://i.scdn.co/image/abc"}
        """)
        let service = SpotifyPlaylistMetadataService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchMetadata(for: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6")
        guard case .success(let metadata) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(metadata.title, "Deep Focus")
        XCTAssertEqual(metadata.typeLabel, "Offentlig playliste")
        XCTAssertEqual(metadata.thumbnailURL?.absoluteString, "https://i.scdn.co/image/abc")
    }

    func testOpenSpotifyURLProducesSameMetadata() async {
        let session = makeStubSession(statusCode: 200, body: """
        {"title":"Coding Mode","type":"playlist","thumbnail_url":"https://i.scdn.co/image/xyz"}
        """)
        let service = SpotifyPlaylistMetadataService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchMetadata(for: "https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6")
        guard case .success(let metadata) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(metadata.title, "Coding Mode")
        XCTAssertEqual(metadata.typeLabel, "Offentlig playliste")
        XCTAssertEqual(metadata.thumbnailURL?.absoluteString, "https://i.scdn.co/image/xyz")
    }

    func testHTTP429MapsToRateLimited() async {
        let session = makeStubSession(statusCode: 429, body: "{}")
        let service = SpotifyPlaylistMetadataService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchMetadata(for: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6")
        XCTAssertEqual(result, .rateLimited)
    }

    func testInvalidJSONMapsToDecodingError() async {
        let session = makeStubSession(statusCode: 200, body: "{not-json")
        let service = SpotifyPlaylistMetadataService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchMetadata(for: "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6")
        XCTAssertEqual(result, .decodingError)
    }

    func testInvalidInputMapsToInvalidPlaylist() async {
        let session = makeStubSession(statusCode: 200, body: "{}")
        let service = SpotifyPlaylistMetadataService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchMetadata(for: "not-a-playlist")
        XCTAssertEqual(result, .invalidPlaylist)
    }

    func testCacheHitAvoidsSecondNetworkCall() async {
        let session = makeStubSession(statusCode: 200, body: """
        {"title":"Cache Me","type":"playlist","thumbnail_url":"https://i.scdn.co/image/cache"}
        """)
        let service = SpotifyPlaylistMetadataService(session: session, cacheTTL: 600, timeout: 7)
        let input = "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"

        _ = await service.fetchMetadata(for: input)
        _ = await service.fetchMetadata(for: input)

        XCTAssertEqual(URLProtocolStub.requestCount, 1)
    }

    private func makeStubSession(statusCode: Int, body: String) -> URLSession {
        URLProtocolStub.handler = { request in
            let url = request.url ?? URL(string: "https://open.spotify.com/oembed")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body.data(using: .utf8) ?? Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.requestCount += 1
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
