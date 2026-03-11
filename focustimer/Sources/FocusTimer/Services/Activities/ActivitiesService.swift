import Foundation

struct TiimoActivitiesConfiguration {
    let baseURL: URL
    let profileID: String
    let accessToken: String?

    static let defaultProfileID = "1c820971-91d7-4794-8623-bc9ff211a202"

    static var `default`: TiimoActivitiesConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let baseURL = URL(string: environment["FOCUSTIMER_TIIMO_BASE_URL"] ?? "https://test1api.tiimoapp.com")
            ?? URL(string: "https://test1api.tiimoapp.com")!
        let profileID = environment["FOCUSTIMER_TIIMO_PROFILE_ID"] ?? defaultProfileID
        let token = environment["FOCUSTIMER_TIIMO_ACCESS_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TiimoActivitiesConfiguration(
            baseURL: baseURL,
            profileID: profileID,
            accessToken: token?.isEmpty == true ? nil : token
        )
    }
}

struct TiimoActivity: Equatable {
    enum ActivityType: Equatable {
        case play
        case other
    }

    let id: String
    let title: String
    let startAt: Date?
    let endAt: Date?
    let type: ActivityType
    let groupingLabel: String?
    let durationSeconds: Int?
    let sortPriority: Int?
    let iconID: String?
    let backgroundColorHex: String?

    init(
        id: String,
        title: String,
        startAt: Date?,
        endAt: Date?,
        type: ActivityType = .other,
        groupingLabel: String? = nil,
        durationSeconds: Int? = nil,
        sortPriority: Int? = nil,
        iconID: String? = nil,
        backgroundColorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.type = type
        self.groupingLabel = groupingLabel
        self.durationSeconds = durationSeconds
        self.sortPriority = sortPriority
        self.iconID = iconID
        self.backgroundColorHex = backgroundColorHex
    }
}

enum ActivitiesServiceError: Error, Equatable {
    case missingCredentials
    case invalidRequest
    case unauthorized
    case forbidden
    case invalidProfile
    case rateLimited
    case server(statusCode: Int)
    case decoding
    case network
}

protocol ActivitiesServiceProviding {
    func fetchActivities(profileID: String, from: Date?, to: Date?) async throws -> [TiimoActivity]
}

actor ActivitiesService: ActivitiesServiceProviding {
    private struct Envelope: Decodable {
        let activities: [RawActivity]?
        let items: [RawActivity]?
        let data: [RawActivity]?
    }

    private struct DayBuckets: Decodable {
        let buckets: [String: [RawActivity]]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            buckets = try container.decode([String: [RawActivity]].self)
        }
    }

    private struct RawActivity: Decodable {
        private struct RawGrouping: Decodable {
            let groupingLabel: String?
        }

        let id: String?
        let activityId: String?
        let title: String?
        let name: String?
        let taskTitle: String?
        let type: String?
        let sortPriority: Int?
        let iconID: String?
        let backgroundColor: String?
        let startAt: Date?
        let start: Date?
        let startDate: Date?
        let startTime: Date?
        let startTimeActual: Date?
        let endAt: Date?
        let end: Date?
        let endDate: Date?
        let endTime: Date?
        let endTimeActual: Date?
        let duration: Int?
        let durationActual: Int?
        private let grouping: RawGrouping?

        enum CodingKeys: String, CodingKey {
            case id
            case activityId
            case title
            case name
            case taskTitle
            case type
            case sortPriority
            case iconID = "iconId"
            case backgroundColor
            case startAt
            case start
            case startDate
            case startTime
            case startTimeActual
            case endAt
            case end
            case endDate
            case endTime
            case endTimeActual
            case duration
            case durationActual
            case grouping
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeTrimmedString([.id])
            activityId = container.decodeTrimmedString([.activityId])
            title = container.decodeTrimmedString([.title])
            name = container.decodeTrimmedString([.name])
            taskTitle = container.decodeTrimmedString([.taskTitle])
            type = container.decodeTrimmedString([.type])
            sortPriority = try? container.decodeIfPresent(Int.self, forKey: .sortPriority)
            iconID = container.decodeTrimmedString([.iconID])
            backgroundColor = container.decodeTrimmedString([.backgroundColor])
            startAt = container.decodeDateValue(forAnyOf: [.startAt])
            start = container.decodeDateValue(forAnyOf: [.start])
            startDate = container.decodeDateValue(forAnyOf: [.startDate])
            startTime = container.decodeDateValue(forAnyOf: [.startTime])
            startTimeActual = container.decodeDateValue(forAnyOf: [.startTimeActual])
            endAt = container.decodeDateValue(forAnyOf: [.endAt])
            end = container.decodeDateValue(forAnyOf: [.end])
            endDate = container.decodeDateValue(forAnyOf: [.endDate])
            endTime = container.decodeDateValue(forAnyOf: [.endTime])
            endTimeActual = container.decodeDateValue(forAnyOf: [.endTimeActual])
            duration = try? container.decodeIfPresent(Int.self, forKey: .duration)
            durationActual = try? container.decodeIfPresent(Int.self, forKey: .durationActual)
            grouping = try? container.decodeIfPresent(RawGrouping.self, forKey: .grouping)
        }

        var mapped: TiimoActivity? {
            let resolvedID = id ?? activityId ?? UUID().uuidString
            let resolvedTitle = title ?? name ?? taskTitle ?? "Untitled task"
            let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let resolvedType: TiimoActivity.ActivityType = normalizedType == "play" ? .play : .other
            return TiimoActivity(
                id: resolvedID,
                title: resolvedTitle,
                startAt: startAt ?? start ?? startDate ?? startTime ?? startTimeActual,
                endAt: endAt ?? end ?? endDate ?? endTime ?? endTimeActual,
                type: resolvedType,
                groupingLabel: grouping?.groupingLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                durationSeconds: duration ?? durationActual,
                sortPriority: sortPriority,
                iconID: iconID,
                backgroundColorHex: backgroundColor
            )
        }
    }

    private let baseURL: URL
    private let accessTokenProvider: () -> String?
    private let session: URLSession
    private static let queryDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(
        baseURL: URL = TiimoActivitiesConfiguration.default.baseURL,
        accessTokenProvider: @escaping () -> String? = { TiimoActivitiesConfiguration.default.accessToken },
        session: URLSession? = nil,
        timeout: TimeInterval = 8
    ) {
        self.baseURL = baseURL
        self.accessTokenProvider = accessTokenProvider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchActivities(profileID: String, from: Date?, to: Date?) async throws -> [TiimoActivity] {
        let trimmedProfileID = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfileID.isEmpty else {
            throw ActivitiesServiceError.invalidRequest
        }

        guard let token = accessTokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw ActivitiesServiceError.missingCredentials
        }

        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/profiles/\(trimmedProfileID)/activities"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ActivitiesServiceError.invalidRequest
        }

        var queryItems: [URLQueryItem] = []
        if let from {
            queryItems.append(URLQueryItem(name: "fromDate", value: iso8601String(from)))
        }
        if let to {
            queryItems.append(URLQueryItem(name: "toDate", value: iso8601String(to)))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw ActivitiesServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-GB", forHTTPHeaderField: "Accept-Language")
        request.setValue("tiimo/2.20.17 (com.tiimo.app; build:2; iOS 16.1.1) Alamofire/5.8.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ActivitiesServiceError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw ActivitiesServiceError.network
        }
        logResponse(http)

        switch http.statusCode {
        case 200 ... 299:
            break
        case 400, 404:
            throw ActivitiesServiceError.invalidProfile
        case 401:
            throw ActivitiesServiceError.unauthorized
        case 403:
            throw ActivitiesServiceError.forbidden
        case 429:
            throw ActivitiesServiceError.rateLimited
        case 500 ... 599:
            throw ActivitiesServiceError.server(statusCode: http.statusCode)
        default:
            throw ActivitiesServiceError.network
        }

        if let activities = tryDecode([RawActivity].self, from: data) {
            return activities.compactMap(\.mapped)
        }
        if let envelope = tryDecode(Envelope.self, from: data),
           envelope.activities != nil || envelope.items != nil || envelope.data != nil
        {
            let raw = envelope.activities ?? envelope.items ?? envelope.data ?? []
            return raw.compactMap(\.mapped)
        }
        if let dayBuckets = tryDecode(DayBuckets.self, from: data) {
            let flattened = dayBuckets.buckets.values.flatMap { $0 }.compactMap(\.mapped)
            if !flattened.isEmpty {
                return flattened
            }
        }
        throw ActivitiesServiceError.decoding
    }

    private func tryDecode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }

    private func iso8601String(_ date: Date) -> String {
        Self.queryDateFormatter.string(from: date)
    }

    private func logResponse(_ response: HTTPURLResponse) {
        let requestID = response.value(forHTTPHeaderField: "x-request-id")
            ?? response.value(forHTTPHeaderField: "request-id")
            ?? "-"
        FocusTimerDebugLog.ai("Activities API status=\(response.statusCode) requestID=\(requestID)")
    }
}

private extension KeyedDecodingContainer where Key: CodingKey {
    func decodeTrimmedString(_ keys: [Key]) -> String? {
        for key in keys {
            if let value = (try? decodeIfPresent(String.self, forKey: key))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    func decodeDateValue(forAnyOf keys: [Key]) -> Date? {
        for key in keys {
            if let date = try? decodeIfPresent(Date.self, forKey: key) {
                return date
            }
            if let unix = try? decodeIfPresent(Double.self, forKey: key) {
                if unix > 0 {
                    return Date(timeIntervalSince1970: unix)
                }
            }
            if let unixInt = try? decodeIfPresent(Int.self, forKey: key), unixInt > 0 {
                return Date(timeIntervalSince1970: TimeInterval(unixInt))
            }
            if let value = try? decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                if let parsed = DateParsers.iso8601WithFractional.date(from: value)
                    ?? DateParsers.iso8601.date(from: value)
                    ?? DateParsers.rfc3339.date(from: value)
                    ?? DateParsers.iso8601NoTimezone.date(from: value)
                {
                    return parsed
                }
            }
        }
        return nil
    }
}

private enum DateParsers {
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let rfc3339: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    static let iso8601NoTimezone: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
