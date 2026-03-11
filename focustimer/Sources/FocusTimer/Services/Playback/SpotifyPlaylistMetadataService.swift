import Foundation

struct SpotifyPlaylistMetadata: Equatable {
    let title: String
    let typeLabel: String
    let thumbnailURL: URL?
    let sourceURL: URL
}

enum SpotifyPlaylistMetadataResult: Equatable {
    case success(SpotifyPlaylistMetadata)
    case invalidPlaylist
    case networkError
    case decodingError
    case rateLimited
}

protocol SpotifyPlaylistMetadataProviding {
    func fetchMetadata(for playlistInput: String) async -> SpotifyPlaylistMetadataResult
}

actor SpotifyPlaylistMetadataService: SpotifyPlaylistMetadataProviding {
    private struct OEmbedResponse: Decodable {
        let title: String?
        let thumbnailURL: URL?

        enum CodingKeys: String, CodingKey {
            case title
            case thumbnailURL = "thumbnail_url"
        }
    }

    private struct CacheEntry {
        let metadata: SpotifyPlaylistMetadata
        let expiresAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let session: URLSession
    private let cacheTTL: TimeInterval

    init(
        session: URLSession? = nil,
        cacheTTL: TimeInterval = 600,
        timeout: TimeInterval = 7
    ) {
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

    func fetchMetadata(for playlistInput: String) async -> SpotifyPlaylistMetadataResult {
        guard let playlistURI = SpotifyPlaybackController.normalizedPlaylistURI(from: playlistInput),
              let sourceURL = sourceWebURL(from: playlistURI)
        else {
            return .invalidPlaylist
        }

        let cacheKey = cacheKeyForPlaylistURI(playlistURI)
        if let entry = cache[cacheKey], entry.expiresAt > Date() {
            return .success(entry.metadata)
        }

        guard let requestURL = oEmbedURL(for: sourceURL) else {
            return .invalidPlaylist
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError
            }
            if http.statusCode == 429 {
                return .rateLimited
            }
            guard (200 ... 299).contains(http.statusCode) else {
                return .networkError
            }

            let parsed: OEmbedResponse
            do {
                parsed = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            } catch {
                return .decodingError
            }

            let metadata = SpotifyPlaylistMetadata(
                title: normalizedTitle(parsed.title),
                typeLabel: "Offentlig playliste",
                thumbnailURL: parsed.thumbnailURL,
                sourceURL: sourceURL
            )
            cache[cacheKey] = CacheEntry(metadata: metadata, expiresAt: Date().addingTimeInterval(cacheTTL))
            return .success(metadata)
        } catch {
            return .networkError
        }
    }

    private func oEmbedURL(for sourceURL: URL) -> URL? {
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: sourceURL.absoluteString)
        ]
        return components?.url
    }

    private func cacheKeyForPlaylistURI(_ playlistURI: String) -> String {
        playlistURI.replacingOccurrences(of: "spotify:playlist:", with: "")
    }

    private func sourceWebURL(from playlistURI: String) -> URL? {
        let id = cacheKeyForPlaylistURI(playlistURI)
        guard !id.isEmpty else { return nil }
        return URL(string: "https://open.spotify.com/playlist/\(id)")
    }

    private func normalizedTitle(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Focus Playlist" : trimmed
    }
}
