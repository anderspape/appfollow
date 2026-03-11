import Foundation

enum TaskTemplateSource: String, Codable, Equatable {
    case user
    case premade
}

struct TaskTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var emoji: String
    var accentHex: String
    var focusMinutes: Int
    var subTasks: [FocusTask]
    var subTaskTimersEnabled: Bool
    var categoryName: String?
    var source: TaskTemplateSource
    var premadeTemplateID: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case emoji
        case accentHex
        case focusMinutes
        case subTasks
        case subTaskTimersEnabled
        case categoryName
        case source
        case premadeTemplateID
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        emoji: String,
        accentHex: String,
        focusMinutes: Int,
        subTasks: [FocusTask] = [],
        subTaskTimersEnabled: Bool = false,
        categoryName: String? = nil,
        source: TaskTemplateSource = .user,
        premadeTemplateID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        let createdAt = createdAt
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? FocusSettings.default.sessionTitle
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike()
            ?? FocusSettings.default.sessionEmoji
        self.accentHex = HexColor.normalize(accentHex) ?? FocusSettings.default.sessionAccentHex
        self.focusMinutes = min(180, max(1, focusMinutes))
        self.subTasks = subTasks
        self.subTaskTimersEnabled = subTaskTimersEnabled
        self.categoryName = SessionCategory.named(categoryName ?? "")?.name
        self.source = source
        self.premadeTemplateID = premadeTemplateID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    var effectiveFocusMinutes: Int {
        if subTaskTimersEnabled, !subTasks.isEmpty {
            return min(180, max(1, subTasks.reduce(0) { $0 + max(1, $1.durationMinutes) }))
        }
        return min(180, max(1, focusMinutes))
    }

    var favoriteSignature: String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedEmojiValue = emoji.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike()
            ?? FocusSettings.default.sessionEmoji
        let normalizedHex = HexColor.normalize(accentHex) ?? FocusSettings.default.sessionAccentHex
        let normalizedMinutes = max(1, effectiveFocusMinutes)
        let normalizedSubtasks = subTasks.compactMap { task -> String? in
            let taskTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !taskTitle.isEmpty else { return nil }

            let taskEmoji = task.emoji.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike()
                ?? FocusTask.defaultEmoji
            let taskHex = HexColor.normalize(task.accentHex) ?? FocusSettings.default.sessionAccentHex
            return "\(taskTitle)|\(taskEmoji)|\(max(1, task.durationMinutes))|\(taskHex)"
        }

        return [
            normalizedTitle,
            normalizedEmojiValue,
            normalizedHex,
            "\(normalizedMinutes)",
            subTaskTimersEnabled ? "timed" : "flat",
            normalizedSubtasks.joined(separator: "||")
        ].joined(separator: "###")
    }

    var resolvedCategoryName: String? {
        if let categoryName, let category = SessionCategory.named(categoryName) {
            return category.name
        }
        if let matchedByTitle = SessionCategory.match(in: title) {
            return matchedByTitle.name
        }
        return SessionCategory.match(colorHex: accentHex)?.name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? FocusSettings.default.sessionTitle
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? FocusSettings.default.sessionEmoji
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? FocusSettings.default.sessionAccentHex
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? FocusSettings.default.focusMinutes
        subTasks = try container.decodeIfPresent([FocusTask].self, forKey: .subTasks) ?? []
        subTaskTimersEnabled = try container.decodeIfPresent(Bool.self, forKey: .subTaskTimersEnabled) ?? false
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        source = try container.decodeIfPresent(TaskTemplateSource.self, forKey: .source) ?? .user
        premadeTemplateID = try container.decodeIfPresent(String.self, forKey: .premadeTemplateID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt

        title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FocusSettings.default.sessionTitle : title.trimmingCharacters(in: .whitespacesAndNewlines)
        emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike() ?? FocusSettings.default.sessionEmoji
        accentHex = HexColor.normalize(accentHex) ?? FocusSettings.default.sessionAccentHex
        focusMinutes = min(180, max(1, focusMinutes))
        categoryName = SessionCategory.named(categoryName ?? "")?.name
        premadeTemplateID = premadeTemplateID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func asUserCopy(now: Date = Date()) -> TaskTemplate {
        TaskTemplate(
            title: title,
            emoji: emoji,
            accentHex: accentHex,
            focusMinutes: focusMinutes,
            subTasks: subTasks.map { task in
                FocusTask(
                    emoji: task.emoji,
                    title: task.title,
                    durationMinutes: task.durationMinutes,
                    accentHex: task.accentHex,
                    isDone: false
                )
            },
            subTaskTimersEnabled: subTaskTimersEnabled,
            categoryName: resolvedCategoryName,
            source: .user,
            premadeTemplateID: premadeTemplateID,
            createdAt: now,
            updatedAt: now
        )
    }
}
