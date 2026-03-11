import XCTest
@testable import FocusTimer

final class TiimoMusicChannelsServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        TiimoChannelsURLProtocolStub.handler = nil
        TiimoChannelsURLProtocolStub.requestCount = 0
    }

    func testWrapperPayloadParsesChannelsAndLocalizedText() async {
        let session = makeStubSession(statusCode: 200, body: """
        {
          "channels": [
            {"name":"Lo-Fi","color":"#D9CEFF","fileUrl":"https://cdn.example.com/lofi.m4a","coverUrl":"https://cdn.example.com/lofi.png"},
            {"name":"Celestial","color":"#DEE4FF","fileUrl":"https://cdn.example.com/celestial.m4a","coverUrl":"https://cdn.example.com/celestial.png"}
          ],
          "localizedListenersText": "Lyttere"
        }
        """)
        let service = TiimoMusicChannelsService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchChannels(locale: "da-DK")
        guard case .success(let payload) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(payload.channels.count, 2)
        XCTAssertEqual(payload.channels.first?.name, "Lo-Fi")
        XCTAssertEqual(payload.channels.first?.coverURL?.absoluteString, "https://cdn.example.com/lofi.png")
        XCTAssertEqual(payload.localizedListenersText, "Lyttere")
    }

    func testArrayPayloadParsesWithoutWrapper() async {
        let session = makeStubSession(statusCode: 200, body: """
        [
          {"name":"Solo","color":"#000000","fileUrl":"https://cdn.example.com/solo.m4a","coverUrl":null}
        ]
        """)
        let service = TiimoMusicChannelsService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchChannels(locale: nil)
        guard case .success(let payload) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(payload.channels.count, 1)
        XCTAssertEqual(payload.channels[0].name, "Solo")
        XCTAssertNil(payload.localizedListenersText)
    }

    func testInvalidFileURLsAreDropped() async {
        let session = makeStubSession(statusCode: 200, body: """
        {
          "channels": [
            {"name":"Bad","color":"#fff","fileUrl":"","coverUrl":null},
            {"name":"Good","color":"#111","fileUrl":"https://cdn.example.com/good.m4a","coverUrl":null}
          ]
        }
        """)
        let service = TiimoMusicChannelsService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchChannels(locale: nil)
        guard case .success(let payload) = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(payload.channels.count, 1)
        XCTAssertEqual(payload.channels[0].name, "Good")
    }

    func testCacheHitAvoidsSecondNetworkCall() async {
        let session = makeStubSession(statusCode: 200, body: """
        {
          "channels": [
            {"name":"Cache","color":"#fff","fileUrl":"https://cdn.example.com/cache.m4a","coverUrl":null}
          ]
        }
        """)
        let service = TiimoMusicChannelsService(session: session, cacheTTL: 600, timeout: 7)

        _ = await service.fetchChannels(locale: nil)
        _ = await service.fetchChannels(locale: nil)

        XCTAssertEqual(TiimoChannelsURLProtocolStub.requestCount, 1)
    }

    func testNetworkErrorMapsToFailure() async {
        let session = makeStubSession(statusCode: 503, body: "{}")
        let service = TiimoMusicChannelsService(session: session, cacheTTL: 600, timeout: 7)

        let result = await service.fetchChannels(locale: nil)
        XCTAssertEqual(result, .failure(.network))
    }

    private func makeStubSession(statusCode: Int, body: String) -> URLSession {
        TiimoChannelsURLProtocolStub.handler = { request in
            let url = request.url ?? URL(string: "https://api.tiimoapp.com/api/premade/music-channels")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body.data(using: .utf8) ?? Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TiimoChannelsURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class TiimoChannelsURLProtocolStub: URLProtocol {
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
