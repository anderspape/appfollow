import Foundation
import AppKit

enum FocusMusicProvider: String, Codable, Equatable, CaseIterable {
    case spotify
    case tiimoRadio

    var title: String {
        switch self {
        case .spotify:
            return "Spotify"
        case .tiimoRadio:
            return "Tiimo Radio"
        }
    }
}

enum FocusMusicControlResult: Equatable {
    case success
    case appNotInstalled
    case permissionDenied
    case invalidPlaylist
    case commandFailed(String)
}

struct FocusMusicPlaybackSnapshot: Equatable {
    let isPlaying: Bool
    let isMuted: Bool
    let trackTitle: String?
    let artistName: String?
    let albumTitle: String?
    let artworkURL: URL?
    let playbackPositionSeconds: Double?
    let trackDurationSeconds: Double?
}

protocol FocusMusicControlling {
    func play(playlist: String?) async -> FocusMusicControlResult
    func pause() async -> FocusMusicControlResult
    func next() async -> FocusMusicControlResult
    func previous() async -> FocusMusicControlResult
    func seek(by seconds: Int) async -> FocusMusicControlResult
    func adjustVolume(by delta: Int) async -> FocusMusicControlResult
    func setMuted(_ muted: Bool) async -> FocusMusicControlResult
    func openInSpotify(playlist: String?) async -> FocusMusicControlResult
    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot?
}

struct SpotifyPlaybackController: FocusMusicControlling {
    private let spotifyBundleID = "com.spotify.client"
    private enum AppleScriptExecutionResult {
        case success(NSAppleEventDescriptor)
        case failure(FocusMusicControlResult)
    }

    func play(playlist: String?) async -> FocusMusicControlResult {
        guard isSpotifyInstalled else { return .appNotInstalled }
        let wasRunning = isSpotifyRunning
        if !wasRunning {
            _ = launchSpotifyBackground()
            try? await Task.sleep(nanoseconds: 220_000_000)
        }

        let trimmedInput = playlist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedPlaylistURI = Self.normalizedPlaylistURI(from: trimmedInput)
        if !trimmedInput.isEmpty, normalizedPlaylistURI == nil {
            return .invalidPlaylist
        }

        // Prefer plain resume/play first; targeting a playlist via deep-link can foreground Spotify.
        let playResult = runAppleScript("""
        tell application "Spotify"
            play
        end tell
        """)
        if playResult == .success {
            return .success
        }

        // Fallback only when Spotify is already running and a valid playlist was provided.
        guard wasRunning, let normalizedPlaylistURI else {
            return playResult
        }

        return runAppleScript("""
        tell application "Spotify"
            play track "\(normalizedPlaylistURI)"
        end tell
        """)
    }

    func pause() async -> FocusMusicControlResult {
        runAppleScript("""
        tell application "Spotify"
            pause
        end tell
        """)
    }

    func next() async -> FocusMusicControlResult {
        runAppleScript("""
        tell application "Spotify"
            next track
        end tell
        """)
    }

    func previous() async -> FocusMusicControlResult {
        runAppleScript("""
        tell application "Spotify"
            previous track
        end tell
        """)
    }

    func seek(by seconds: Int) async -> FocusMusicControlResult {
        runAppleScript("""
        tell application "Spotify"
            set currentPos to player position
            set targetPos to currentPos + (\(seconds))
            if targetPos < 0 then set targetPos to 0
            set player position to targetPos
        end tell
        """)
    }

    func adjustVolume(by delta: Int) async -> FocusMusicControlResult {
        runAppleScript("""
        tell application "Spotify"
            set currentVolume to sound volume
            set nextVolume to currentVolume + (\(delta))
            if nextVolume < 0 then set nextVolume to 0
            if nextVolume > 100 then set nextVolume to 100
            set sound volume to nextVolume
        end tell
        """)
    }

    func setMuted(_ muted: Bool) async -> FocusMusicControlResult {
        runAppleScript("""
        tell application "Spotify"
            set sound volume to \(muted ? 0 : 80)
        end tell
        """)
    }

    func openInSpotify(playlist: String?) async -> FocusMusicControlResult {
        guard isSpotifyInstalled else { return .appNotInstalled }
        guard let playlistURI = Self.normalizedPlaylistURI(from: playlist),
              let url = Self.openURL(from: playlistURI)
        else {
            return .invalidPlaylist
        }

        return NSWorkspace.shared.open(url) ? .success : .commandFailed("Could not open Spotify URL.")
    }

    func playbackSnapshot() async -> FocusMusicPlaybackSnapshot? {
        guard isSpotifyInstalled, isSpotifyRunning else { return nil }

        let result = runAppleScriptValue("""
        tell application "Spotify"
            set isPlayingFlag to 0
            if player state is playing then set isPlayingFlag to 1
            set currentTitle to ""
            set currentArtist to ""
            set currentAlbum to ""
            set currentArtworkURL to ""
            try
                set currentTitle to name of current track
                set currentArtist to artist of current track
                set currentAlbum to album of current track
                set currentArtworkURL to artwork url of current track
            end try
            set currentPosition to player position
            set currentDurationMs to 0
            try
                set currentDurationMs to duration of current track
            end try
            set currentVolume to sound volume
            return (isPlayingFlag as text) & "||" & currentTitle & "||" & currentArtist & "||" & currentAlbum & "||" & (currentVolume as text) & "||" & currentArtworkURL & "||" & (currentPosition as text) & "||" & (currentDurationMs as text)
        end tell
        """)

        guard case .success(let descriptor) = result,
              let raw = descriptor.stringValue
        else {
            return nil
        }

        let components = raw
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        guard components.count >= 8 else { return nil }

        let playingFlag = components[0]
        let volume = Int(components[4]) ?? 80
        let artworkURL = URL(string: components[5])
        let playbackPositionSeconds = Self.parseAppleScriptNumber(components[6])
        let durationMs = Self.parseAppleScriptNumber(components[7])
        let trackDurationSeconds: Double? = {
            guard let durationMs, durationMs > 0 else { return nil }
            return durationMs / 1000.0
        }()

        return FocusMusicPlaybackSnapshot(
            isPlaying: playingFlag == "1",
            isMuted: volume == 0,
            trackTitle: components[1].isEmpty ? nil : components[1],
            artistName: components[2].isEmpty ? nil : components[2],
            albumTitle: components[3].isEmpty ? nil : components[3],
            artworkURL: artworkURL,
            playbackPositionSeconds: playbackPositionSeconds,
            trackDurationSeconds: trackDurationSeconds
        )
    }

    static func normalizedPlaylistURI(from input: String?) -> String? {
        guard let rawInput = input?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawInput.isEmpty
        else {
            return nil
        }

        if rawInput.hasPrefix("spotify:playlist:") {
            let components = rawInput.split(separator: ":")
            guard components.count >= 3 else { return nil }
            let id = String(components[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            return isLikelySpotifyID(id) ? "spotify:playlist:\(id)" : nil
        }

        if let url = URL(string: rawInput),
           let host = url.host?.lowercased(),
           host.contains("spotify.com")
        {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let playlistIndex = parts.firstIndex(of: "playlist"), playlistIndex + 1 < parts.count {
                let id = parts[playlistIndex + 1]
                return isLikelySpotifyID(id) ? "spotify:playlist:\(id)" : nil
            }
        }

        if isLikelySpotifyID(rawInput) {
            return "spotify:playlist:\(rawInput)"
        }

        return nil
    }

    static func openURL(from playlistURI: String) -> URL? {
        if playlistURI.hasPrefix("spotify:playlist:") {
            if let uriURL = URL(string: playlistURI) {
                return uriURL
            }

            let id = playlistURI.replacingOccurrences(of: "spotify:playlist:", with: "")
            return URL(string: "https://open.spotify.com/playlist/\(id)")
        }

        if let normalized = normalizedPlaylistURI(from: playlistURI) {
            return openURL(from: normalized)
        }

        return URL(string: playlistURI)
    }

    private var isSpotifyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyBundleID) != nil
    }

    private var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleID).isEmpty
    }

    private func launchSpotifyBackground() -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyBundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        return true
    }

    private func runAppleScript(_ source: String) -> FocusMusicControlResult {
        switch runAppleScriptValue(source) {
        case .success:
            return .success
        case .failure(let error):
            return error
        }
    }

    private func runAppleScriptValue(_ source: String) -> AppleScriptExecutionResult {
        guard isSpotifyInstalled else { return .failure(.appNotInstalled) }
        guard let script = NSAppleScript(source: source) else {
            return .failure(.commandFailed("Could not compile AppleScript."))
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .success(descriptor) }

        let errorCode = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        let errorMessage = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error."

        if errorCode == -1743 {
            return .failure(.permissionDenied)
        }
        if errorCode == -600 {
            return .failure(.appNotInstalled)
        }
        return .failure(.commandFailed(errorMessage))
    }

    private static func isLikelySpotifyID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (10...64).contains(trimmed.count) else { return false }
        let allowed = CharacterSet.alphanumerics
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func parseAppleScriptNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "missing value" else { return nil }

        // AppleScript can return locale-formatted decimals; normalize to a parseable representation.
        let normalized: String = {
            let compact = trimmed.replacingOccurrences(of: " ", with: "")
            let hasComma = compact.contains(",")
            let hasDot = compact.contains(".")

            if hasComma && hasDot {
                if let lastComma = compact.lastIndex(of: ","),
                   let lastDot = compact.lastIndex(of: "."),
                   lastComma > lastDot
                {
                    return compact
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                }
                return compact.replacingOccurrences(of: ",", with: "")
            }
            if hasComma {
                return compact.replacingOccurrences(of: ",", with: ".")
            }
            return compact
        }()

        return Double(normalized)
    }
}
