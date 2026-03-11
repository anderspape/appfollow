import XCTest
@testable import FocusTimer

final class ActivitiesServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ActivitiesURLProtocolStub.handler = nil
    }

    func testFetchActivitiesUsesBearerAndProfilePath() async throws {
        let expectedToken = "abc123"
        let expectedProfile = "profile-1"
        let session = makeStubSession(statusCode: 200, body: """
        [
          {
            "id": "a1",
            "title": "Morning planning",
            "startAt": "2026-02-24T08:00:00Z",
            "endAt": "2026-02-24T08:30:00Z"
          }
        ]
        """) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedToken)")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/api/profiles/\(expectedProfile)/activities") == true)
        }

        let service = ActivitiesService(
            baseURL: URL(string: "https://test1api.tiimoapp.com")!,
            accessTokenProvider: { expectedToken },
            session: session
        )

        let activities = try await service.fetchActivities(profileID: expectedProfile, from: nil, to: nil)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.title, "Morning planning")
    }

    func testFetchActivitiesMapsUnauthorizedError() async {
        let session = makeStubSession(statusCode: 401, body: "{}")
        let service = ActivitiesService(
            baseURL: URL(string: "https://test1api.tiimoapp.com")!,
            accessTokenProvider: { "token" },
            session: session
        )

        do {
            _ = try await service.fetchActivities(profileID: "profile-1", from: nil, to: nil)
            XCTFail("Expected unauthorized error")
        } catch let error as ActivitiesServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchActivitiesDecodesEnvelopeShape() async throws {
        let session = makeStubSession(statusCode: 200, body: """
        {
          "activities": [
            {
              "activityId": "x2",
              "name": "Walk",
              "start": "2026-02-24T09:00:00Z",
              "end": "2026-02-24T09:20:00Z"
            }
          ]
        }
        """)
        let service = ActivitiesService(
            baseURL: URL(string: "https://test1api.tiimoapp.com")!,
            accessTokenProvider: { "token" },
            session: session
        )

        let activities = try await service.fetchActivities(profileID: "profile-1", from: nil, to: nil)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].id, "x2")
        XCTAssertEqual(activities[0].title, "Walk")
    }

    func testFetchActivitiesUsesFromDateAndToDateQueryItems() async throws {
        let from = Date(timeIntervalSince1970: 1_771_970_838)
        let to = Date(timeIntervalSince1970: 1_771_970_938)
        let session = makeStubSession(statusCode: 200, body: "[]") { request in
            let url = request.url?.absoluteString ?? ""
            XCTAssertTrue(url.contains("fromDate="))
            XCTAssertTrue(url.contains("toDate="))
        }

        let service = ActivitiesService(
            baseURL: URL(string: "https://test1api.tiimoapp.com")!,
            accessTokenProvider: { "token" },
            session: session
        )

        _ = try await service.fetchActivities(profileID: "profile-1", from: from, to: to)
    }

    func testFetchActivitiesDecodesDateBucketPayloadWithStartTimeFields() async throws {
        let session = makeStubSession(statusCode: 200, body: """
        {
          "2026-02-24": [
            {
              "activityId": "3197f686-d658-4a4f-21f5-08de33de66ec",
              "title": "Pendle til arbejde",
              "iconId": "🚗",
              "backgroundColor": "#FFB0D9",
              "startTime": "2026-02-24T00:00:00",
              "endTime": "2026-02-24T00:30:00"
            }
          ]
        }
        """)
        let service = ActivitiesService(
            baseURL: URL(string: "https://test1api.tiimoapp.com")!,
            accessTokenProvider: { "token" },
            session: session
        )

        let activities = try await service.fetchActivities(profileID: "profile-1", from: nil, to: nil)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.id, "3197f686-d658-4a4f-21f5-08de33de66ec")
        XCTAssertEqual(activities.first?.title, "Pendle til arbejde")
        XCTAssertNotNil(activities.first?.startAt)
        XCTAssertNotNil(activities.first?.endAt)
        XCTAssertEqual(activities.first?.iconID, "🚗")
        XCTAssertEqual(activities.first?.backgroundColorHex, "#FFB0D9")
    }

    private func makeStubSession(
        statusCode: Int,
        body: String,
        onRequest: ((URLRequest) -> Void)? = nil
    ) -> URLSession {
        ActivitiesURLProtocolStub.handler = { request in
            onRequest?(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://test1api.tiimoapp.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = body.data(using: .utf8) ?? Data()
            return (response, data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ActivitiesURLProtocolStub.self]
        return URLSession(configuration: config)
    }
}

private final class ActivitiesURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
