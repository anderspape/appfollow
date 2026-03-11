import Foundation

enum StatusBarTimerDraftHelpers {
    static func formattedDuration(_ totalMinutes: Int) -> String {
        let clamped = min(180, max(1, totalMinutes))
        let hours = clamped / 60
        let minutes = clamped % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }

    static func durationOptions(maxMinutes: Int) -> [Int] {
        Array(stride(from: 5, through: maxMinutes, by: 5))
    }

    static func normalizedEmoji(_ candidate: String, fallback: String) -> String {
        if let emoji = candidate.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike() {
            return emoji
        }
        if let fallbackEmoji = fallback.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike() {
            return fallbackEmoji
        }
        return FocusSettings.default.sessionEmoji
    }

    static func normalizedTasks(_ tasks: [FocusTask]) -> [FocusTask] {
        tasks.compactMap { task -> FocusTask? in
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            return FocusTask(
                id: task.id,
                emoji: normalizedEmoji(task.emoji, fallback: FocusTask.defaultEmoji),
                title: title,
                durationMinutes: min(120, max(1, task.durationMinutes)),
                accentHex: HexColor.normalize(task.accentHex) ?? FocusTask.defaultAccentHex,
                isDone: task.isDone
            )
        }
    }
}
