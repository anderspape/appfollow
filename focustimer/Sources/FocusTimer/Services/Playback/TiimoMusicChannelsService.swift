import Foundation

struct TiimoMusicChannel: Identifiable, Equatable {
    let id: String
    let name: String
    let colorHex: String?
    let fileURL: URL
    let coverURL: URL?
}

struct TiimoMusicChannelsResult: Equatable {
    let channels: [TiimoMusicChannel]
    let localizedListenersText: String?
}

enum TiimoMusicChannelsError: Error, Equatable {
    case invalidResponse
    case decoding
    case network
    case emptyChannels
}

protocol TiimoMusicChannelsProviding {
    func fetchChannels(locale: String?) async -> Result<TiimoMusicChannelsResult, TiimoMusicChannelsError>
}

actor TiimoMusicChannelsService: TiimoMusicChannelsProviding {
    private struct CacheEntry {
        let result: TiimoMusicChannelsResult
        let expiresAt: Date
    }

    private struct WrapperResponse: Decodable {
        let channels: [RawChannel]?
        let localizedListenersText: String?
    }

    private struct RawChannel: Decodable {
        let name: String?
        let color: String?
        let fileUrl: String?
        let coverUrl: String?
    }

    private let endpoint = URL(string: "https://api.tiimoapp.com/api/premade/music-channels")!
    private let session: URLSession
    private let cacheTTL: TimeInterval
    private var cacheEntry: CacheEntry?

    init(session: URLSession? = nil, cacheTTL: TimeInterval = 600, timeout: TimeInterval = 7) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            self.session = URLSession(configuration: configuration)
        }
        self.cacheTTL = max(30, cacheTTL)
    }

    func fetchChannels(locale: String?) async -> Result<TiimoMusicChannelsResult, TiimoMusicChannelsError> {
        if let cacheEntry, cacheEntry.expiresAt > Date() {
            return .success(cacheEntry.result)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(normalizedLocale(locale), forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode)
            else {
                return .failure(.network)
            }

            guard let result = decodeResult(from: data) else {
                return .failure(.decoding)
            }

            guard !result.channels.isEmpty else {
                return .failure(.emptyChannels)
            }

            cacheEntry = CacheEntry(result: result, expiresAt: Date().addingTimeInterval(cacheTTL))
            return .success(result)
        } catch {
            return .failure(.network)
        }
    }

    private func decodeResult(from data: Data) -> TiimoMusicChannelsResult? {
        let decoder = JSONDecoder()

        if let wrapper = try? decoder.decode(WrapperResponse.self, from: data),
           let channels = wrapper.channels
        {
            let mapped = mapChannels(channels)
            return TiimoMusicChannelsResult(
                channels: mapped,
                localizedListenersText: wrapper.localizedListenersText
            )
        }

        if let rawChannels = try? decoder.decode([RawChannel].self, from: data) {
            return TiimoMusicChannelsResult(
                channels: mapChannels(rawChannels),
                localizedListenersText: nil
            )
        }

        if let singleChannel = try? decoder.decode(RawChannel.self, from: data) {
            return TiimoMusicChannelsResult(
                channels: mapChannels([singleChannel]),
                localizedListenersText: nil
            )
        }

        return nil
    }

    private func mapChannels(_ rawChannels: [RawChannel]) -> [TiimoMusicChannel] {
        rawChannels.compactMap { raw in
            guard let fileRaw = raw.fileUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !fileRaw.isEmpty,
                  let fileURL = URL(string: fileRaw)
            else {
                return nil
            }

            let cleanedName = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let channelName = cleanedName.isEmpty ? "Tiimo Channel" : cleanedName

            let coverURL: URL? = {
                guard let rawCover = raw.coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawCover.isEmpty
                else {
                    return nil
                }
                return URL(string: rawCover)
            }()

            let colorHex = raw.color?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stableID = fileURL.absoluteString.lowercased()

            return TiimoMusicChannel(
                id: stableID,
                name: channelName,
                colorHex: colorHex,
                fileURL: fileURL,
                coverURL: coverURL
            )
        }
    }

    private func normalizedLocale(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        if let preferred = Locale.preferredLanguages.first,
           !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return preferred
        }
        return "en-GB"
    }
}
