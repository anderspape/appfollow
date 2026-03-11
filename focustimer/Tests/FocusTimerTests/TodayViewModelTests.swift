import XCTest
@testable import FocusTimer

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testLoadTodaySuccessSortsAscendingAndSetsLoadedState() async {
        let service = MockActivitiesService()
        let baseDate = Self.makeDate("2026-02-24T10:00:00Z")
        service.result = .success([
            TiimoActivity(id: "2", title: "Second", startAt: Self.makeDate("2026-02-24T12:00:00Z"), endAt: nil),
            TiimoActivity(id: "1", title: "First", startAt: Self.makeDate("2026-02-24T09:00:00Z"), endAt: nil)
        ])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let viewModel = TodayViewModel(
            activitiesService: service,
            profileID: "profile-id",
            calendar: calendar,
            nowProvider: { baseDate }
        )

        await viewModel.loadToday()

        guard case .loaded(let items) = viewModel.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(items.map(\.id), ["1", "2"])
    }

    func testLoadTodayReturnsEmptyWhenNoActivitiesInDay() async {
        let service = MockActivitiesService()
        let baseDate = Self.makeDate("2026-02-24T10:00:00Z")
        service.result = .success([
            TiimoActivity(id: "old", title: "Yesterday", startAt: Self.makeDate("2026-02-23T12:00:00Z"), endAt: nil)
        ])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let viewModel = TodayViewModel(
            activitiesService: service,
            profileID: "profile-id",
            calendar: calendar,
            nowProvider: { baseDate }
        )

        await viewModel.loadToday()
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testLoadTodayMapsUnauthorizedToAuthErrorMessage() async {
        let service = MockActivitiesService()
        service.result = .failure(.unauthorized)

        let viewModel = TodayViewModel(
            activitiesService: service,
            profileID: "profile-id",
            nowProvider: { Self.makeDate("2026-02-24T10:00:00Z") }
        )

        await viewModel.loadToday()
        guard case .error(let message) = viewModel.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertEqual(message, "Du skal logge ind igen for at hente tasks.")
    }

    func testLoadTodayIncludesBoundaryTimes() async {
        let service = MockActivitiesService()
        let baseDate = Self.makeDate("2026-02-24T10:00:00Z")
        service.result = .success([
            TiimoActivity(id: "start", title: "Start", startAt: Self.makeDate("2026-02-24T00:00:00Z"), endAt: nil),
            TiimoActivity(id: "end", title: "End", startAt: Self.makeDate("2026-02-24T23:59:00Z"), endAt: nil)
        ])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let viewModel = TodayViewModel(
            activitiesService: service,
            profileID: "profile-id",
            calendar: calendar,
            nowProvider: { baseDate }
        )

        await viewModel.loadToday()

        guard case .loaded(let items) = viewModel.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(Set(items.map(\.id)), Set(["start", "end"]))
    }

    private static func makeDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }
}

private final class MockActivitiesService: ActivitiesServiceProviding {
    var result: Result<[TiimoActivity], ActivitiesServiceError> = .success([])

    func fetchActivities(profileID: String, from: Date?, to: Date?) async throws -> [TiimoActivity] {
        switch result {
        case .success(let activities):
            return activities
        case .failure(let error):
            throw error
        }
    }
}
