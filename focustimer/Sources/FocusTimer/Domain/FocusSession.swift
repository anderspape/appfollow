import Foundation

enum SessionPhase: String, Codable {
    case focus
    case rest
}

struct FocusTask: Identifiable, Codable, Equatable {
    static let defaultEmoji = "✅"
    static let defaultTitle = "Task"
    static let defaultDurationMinutes = 5
    static let defaultAccentHex = "#ECEBFC"

    let id: UUID
    var emoji: String
    var title: String
    var durationMinutes: Int
    var accentHex: String
    var isDone: Bool

    init(
        id: UUID = UUID(),
        emoji: String,
        title: String,
        durationMinutes: Int = FocusTask.defaultDurationMinutes,
        accentHex: String = FocusTask.defaultAccentHex,
        isDone: Bool
    ) {
        self.id = id
        self.emoji = emoji
        self.title = title
        self.durationMinutes = max(1, durationMinutes)
        self.accentHex = HexColor.normalize(accentHex) ?? FocusTask.defaultAccentHex
        self.isDone = isDone
    }

    enum CodingKeys: String, CodingKey {
        case id
        case emoji
        case title
        case durationMinutes
        case accentHex
        case isDone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? FocusTask.defaultEmoji
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? FocusTask.defaultTitle
        durationMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? FocusTask.defaultDurationMinutes)
        accentHex = HexColor.normalize(
            try container.decodeIfPresent(String.self, forKey: .accentHex) ?? FocusTask.defaultAccentHex
        ) ?? FocusTask.defaultAccentHex
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
    }
}

struct FocusSettings: Codable, Equatable {
    var focusMinutes: Int
    var breakMinutes: Int
    var sessionTitle: String
    var sessionEmoji: String
    var sessionAccentHex: String
    var subTasks: [FocusTask]
    var subTaskTimersEnabled: Bool
    var focusMusicEnabled: Bool
    var focusMusicProvider: FocusMusicProvider
    var spotifyPlaylistURIOrURL: String
    var defaultFallbackMusicChannelID: String?
    var aiEnabled: Bool

    static let defaultSpotifyPlaylistURIOrURL = "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"

    static let `default` = FocusSettings(
        focusMinutes: 25,
        breakMinutes: 5,
        sessionTitle: "Focus",
        sessionEmoji: "🌱",
        sessionAccentHex: "#9E84FF",
        subTasks: [],
        subTaskTimersEnabled: false,
        focusMusicEnabled: false,
        focusMusicProvider: .spotify,
        spotifyPlaylistURIOrURL: defaultSpotifyPlaylistURIOrURL,
        defaultFallbackMusicChannelID: nil,
        aiEnabled: true
    )

    enum CodingKeys: String, CodingKey {
        case focusMinutes
        case breakMinutes
        case sessionTitle
        case sessionEmoji
        case sessionAccentHex
        case subTasks
        case subTaskTimersEnabled
        case focusMusicEnabled
        case focusMusicProvider
        case spotifyPlaylistURIOrURL
        case defaultFallbackMusicChannelID
        case aiEnabled
    }

    init(
        focusMinutes: Int,
        breakMinutes: Int,
        sessionTitle: String,
        sessionEmoji: String,
        sessionAccentHex: String,
        subTasks: [FocusTask],
        subTaskTimersEnabled: Bool,
        focusMusicEnabled: Bool = Self.default.focusMusicEnabled,
        focusMusicProvider: FocusMusicProvider = Self.default.focusMusicProvider,
        spotifyPlaylistURIOrURL: String = Self.default.spotifyPlaylistURIOrURL,
        defaultFallbackMusicChannelID: String? = Self.default.defaultFallbackMusicChannelID,
        aiEnabled: Bool = Self.default.aiEnabled
    ) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.sessionTitle = sessionTitle
        self.sessionEmoji = sessionEmoji
        self.sessionAccentHex = sessionAccentHex
        self.subTasks = subTasks
        self.subTaskTimersEnabled = subTaskTimersEnabled
        self.focusMusicEnabled = focusMusicEnabled
        self.focusMusicProvider = focusMusicProvider
        self.spotifyPlaylistURIOrURL = spotifyPlaylistURIOrURL
        self.defaultFallbackMusicChannelID = defaultFallbackMusicChannelID
        self.aiEnabled = aiEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? Self.default.focusMinutes
        breakMinutes = try container.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? Self.default.breakMinutes
        sessionTitle = try container.decodeIfPresent(String.self, forKey: .sessionTitle) ?? Self.default.sessionTitle
        sessionEmoji = try container.decodeIfPresent(String.self, forKey: .sessionEmoji) ?? Self.default.sessionEmoji
        sessionAccentHex = try container.decodeIfPresent(String.self, forKey: .sessionAccentHex) ?? Self.default.sessionAccentHex
        subTasks = try container.decodeIfPresent([FocusTask].self, forKey: .subTasks) ?? Self.default.subTasks
        subTaskTimersEnabled = try container.decodeIfPresent(Bool.self, forKey: .subTaskTimersEnabled) ?? Self.default.subTaskTimersEnabled
        focusMusicEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusMusicEnabled) ?? Self.default.focusMusicEnabled
        focusMusicProvider = try container.decodeIfPresent(FocusMusicProvider.self, forKey: .focusMusicProvider) ?? Self.default.focusMusicProvider
        spotifyPlaylistURIOrURL = try container.decodeIfPresent(String.self, forKey: .spotifyPlaylistURIOrURL) ?? Self.default.spotifyPlaylistURIOrURL
        defaultFallbackMusicChannelID = try container.decodeIfPresent(String.self, forKey: .defaultFallbackMusicChannelID)
        aiEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? Self.default.aiEnabled
    }
}
