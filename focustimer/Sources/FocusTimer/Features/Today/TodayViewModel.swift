import Foundation

struct TodayTaskItem: Identifiable, Equatable {
    enum Section: String, CaseIterable, Equatable {
        case morning = "Morning"
        case day = "Day"
        case evening = "Evening"
        case other = "Other"

        static let ordered: [Section] = [.morning, .day, .evening, .other]
    }

    enum Kind: Equatable {
        case play
        case scheduled
    }

    let id: String
    let title: String
    let startAt: Date?
    let endAt: Date?
    let durationSeconds: Int?
    let section: Section
    let kind: Kind
    let sortPriority: Int?
    let iconID: String?
    let backgroundColorHex: String?
}

@MainActor
final class TodayViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([TodayTaskItem])
        case empty
        case error(String)
    }

    @Published private(set) var state: State = .idle

    private let activitiesService: ActivitiesServiceProviding
    private let profileID: String
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private var currentLoadTask: Task<Void, Never>?
    private var loadSequence: UInt64 = 0

    init(
        activitiesService: ActivitiesServiceProviding = ActivitiesService(),
        profileID: String = TiimoActivitiesConfiguration.default.profileID,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.activitiesService = activitiesService
        self.profileID = profileID
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    deinit {
        currentLoadTask?.cancel()
    }

    func loadToday() async {
        await performLoad(forceRefresh: false)
    }

    func refresh() async {
        await performLoad(forceRefresh: true)
    }

    private func performLoad(forceRefresh: Bool) async {
        if !forceRefresh, currentLoadTask != nil {
            return
        }

        currentLoadTask?.cancel()
        state = .loading
        loadSequence &+= 1
        let sequence = loadSequence

        let task = Task { [weak self] in
            guard let self else { return }
            let (startOfDay, endOfDay) = todayInterval()

            do {
                let activities = try await fetchActivitiesWithRetry(from: startOfDay, to: endOfDay)
                if Task.isCancelled { return }
                let items = mapToTodayItems(activities, startOfDay: startOfDay, endOfDay: endOfDay)
                if items.isEmpty {
                    state = .empty
                } else {
                    state = .loaded(items)
                }
            } catch let error as ActivitiesServiceError {
                if Task.isCancelled { return }
                state = .error(message(for: error))
            } catch {
                if Task.isCancelled { return }
                state = .error("Kunne ikke hente dagens opgaver lige nu.")
            }
        }

        currentLoadTask = task
        await task.value
        if sequence == loadSequence {
            currentLoadTask = nil
        }
    }

    private func fetchActivitiesWithRetry(from: Date, to: Date) async throws -> [TiimoActivity] {
        do {
            return try await activitiesService.fetchActivities(profileID: profileID, from: from, to: to)
        } catch let error as ActivitiesServiceError {
            if shouldRetry(error: error) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await activitiesService.fetchActivities(profileID: profileID, from: from, to: to)
            }
            throw error
        }
    }

    private func shouldRetry(error: ActivitiesServiceError) -> Bool {
        switch error {
        case .rateLimited, .server, .network:
            return true
        case .missingCredentials, .invalidRequest, .unauthorized, .forbidden, .invalidProfile, .decoding:
            return false
        }
    }

    private func mapToTodayItems(_ activities: [TiimoActivity], startOfDay: Date, endOfDay: Date) -> [TodayTaskItem] {
        activities
            .map { activity in
                TodayTaskItem(
                    id: activity.id,
                    title: activity.title,
                    startAt: activity.startAt,
                    endAt: activity.endAt,
                    durationSeconds: activity.durationSeconds,
                    section: section(from: activity.groupingLabel),
                    kind: activity.type == .play ? .play : .scheduled,
                    sortPriority: activity.sortPriority,
                    iconID: activity.iconID,
                    backgroundColorHex: activity.backgroundColorHex
                )
            }
            .filter { item in
                intersectsDay(item: item, startOfDay: startOfDay, endOfDay: endOfDay)
            }
            .sorted { lhs, rhs in
                if lhs.section != rhs.section {
                    return sortRank(for: lhs.section) < sortRank(for: rhs.section)
                }
                let lhsPriority = lhs.sortPriority ?? Int.max
                let rhsPriority = rhs.sortPriority ?? Int.max
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                let lhsDate = lhs.startAt ?? lhs.endAt ?? .distantFuture
                let rhsDate = rhs.startAt ?? rhs.endAt ?? .distantFuture
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func todayInterval() -> (start: Date, end: Date) {
        let now = nowProvider()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? now
        return (startOfDay, endOfDay)
    }

    private func intersectsDay(item: TodayTaskItem, startOfDay: Date, endOfDay: Date) -> Bool {
        guard let rangeStart = item.startAt ?? item.endAt else {
            return true
        }
        let rangeEnd = item.endAt ?? item.startAt ?? rangeStart
        return rangeStart <= endOfDay && rangeEnd >= startOfDay
    }

    private func section(from groupingLabel: String?) -> TodayTaskItem.Section {
        let normalized = groupingLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "morning": return .morning
        case "day": return .day
        case "evening": return .evening
        default: return .other
        }
    }

    private func sortRank(for section: TodayTaskItem.Section) -> Int {
        TodayTaskItem.Section.ordered.firstIndex(of: section) ?? Int.max
    }

    private func message(for error: ActivitiesServiceError) -> String {
        switch error {
        case .missingCredentials, .unauthorized, .forbidden:
            return "Du skal logge ind igen for at hente tasks."
        case .invalidProfile:
            return "Kunne ikke finde profil for dagens tasks."
        case .rateLimited:
            return "For mange forespørgsler lige nu. Prøv igen om lidt."
        case .server:
            return "Serverfejl hos Tiimo. Prøv igen."
        case .network, .invalidRequest, .decoding:
            return "Kunne ikke hente dagens opgaver lige nu."
        }
    }
}
