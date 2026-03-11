import Foundation

enum SubtaskBreakdownTaskParser {
    private struct Payload: Codable {
        struct Item: Codable {
            let title: String
            let emoji: String
            let durationMinutes: Int
            let accentHex: String
        }

        let tasks: [Item]
    }

    static func parseTasks(
        from text: String,
        totalMinutes: Int,
        defaultPalette: [String]
    ) -> [FocusTask]? {
        guard let json = extractJSONObject(from: text),
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }

        let sanitized: [FocusTask] = payload.tasks
            .prefix(6)
            .compactMap { item in
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let emoji = normalizeEmoji(item.emoji, fallback: FocusTask.defaultEmoji)
                let minutes = min(120, max(1, item.durationMinutes))
                let accent = normalizedAccent(item.accentHex, palette: defaultPalette)
                return FocusTask(
                    emoji: emoji,
                    title: title,
                    durationMinutes: minutes,
                    accentHex: accent,
                    isDone: false
                )
            }

        guard !sanitized.isEmpty else { return nil }
        return rebalance(sanitized, targetTotal: max(1, totalMinutes))
    }

    private static func rebalance(_ tasks: [FocusTask], targetTotal: Int) -> [FocusTask] {
        var result = tasks
        let sum = result.reduce(0) { $0 + $1.durationMinutes }
        guard sum != targetTotal, sum > 0 else { return result }

        let minReachableTotal = result.count
        let maxReachableTotal = result.count * 120
        let clampedTarget = min(max(targetTotal, minReachableTotal), maxReachableTotal)
        guard clampedTarget != sum else { return result }

        let ratio = Double(clampedTarget) / Double(sum)
        for index in result.indices {
            let scaled = Int((Double(result[index].durationMinutes) * ratio).rounded())
            result[index].durationMinutes = min(120, max(1, scaled))
        }

        var adjusted = result.reduce(0) { $0 + $1.durationMinutes }
        var cursor = 0
        while adjusted != clampedTarget, !result.isEmpty {
            let delta = clampedTarget > adjusted ? 1 : -1
            var didAdjustInCycle = false

            for _ in 0 ..< result.count {
                let next = result[cursor].durationMinutes + delta
                if next >= 1, next <= 120 {
                    result[cursor].durationMinutes = next
                    adjusted += delta
                    didAdjustInCycle = true
                    if adjusted == clampedTarget {
                        break
                    }
                }
                cursor = (cursor + 1) % result.count
            }

            if !didAdjustInCycle {
                break
            }
        }
        return result
    }

    private static func normalizedAccent(_ candidate: String, palette: [String]) -> String {
        if let hex = HexColor.normalize(candidate), palette.contains(hex) {
            return hex
        }
        return palette.randomElement() ?? FocusTask.defaultAccentHex
    }

    private static func normalizeEmoji(_ input: String, fallback: String) -> String {
        if let emoji = input.trimmingCharacters(in: .whitespacesAndNewlines).firstEmojiLike() {
            return emoji
        }
        return fallback
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}")
        else {
            return nil
        }
        return String(text[first ... last])
    }
}
