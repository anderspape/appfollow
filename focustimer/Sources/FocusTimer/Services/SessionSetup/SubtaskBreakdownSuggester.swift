import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol SubtaskBreakdownSuggesting {
    func suggestSubtasks(
        title: String,
        totalMinutes: Int,
        current: [FocusTask]
    ) async -> [FocusTask]?
}

struct SubtaskBreakdownSuggester: SubtaskBreakdownSuggesting {
    func suggestSubtasks(
        title: String,
        totalMinutes: Int,
        current: [FocusTask]
    ) async -> [FocusTask]? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
                return await FoundationModelSubtaskBreakdownSuggester().suggestSubtasks(
                    title: trimmedTitle,
                    totalMinutes: totalMinutes,
                    current: current
                )
            }
        #endif

        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct FoundationModelSubtaskBreakdownSuggester {
    private let defaultPalette = ["#EBFCF2", "#FCEDEB", "#FAEFE0", FocusTask.defaultAccentHex, "#E8F4FD", "#F4F0FF"]

    func suggestSubtasks(
        title: String,
        totalMinutes: Int,
        current: [FocusTask]
    ) async -> [FocusTask]? {
        let currentText = current
            .map { "{\"title\":\"\($0.title)\",\"emoji\":\"\($0.emoji)\",\"durationMinutes\":\($0.durationMinutes)}" }
            .joined(separator: ",")

        let instructions = """
        You create concise sub-tasks for a focus timer.
        Return ONLY minified JSON:
        {"tasks":[{"title":"string","emoji":"single emoji","durationMinutes":1...120,"accentHex":"#RRGGBB"}]}
        Rules:
        1) Generate 2-5 practical subtasks for the given title.
        2) Sum of durationMinutes should be close to total focus minutes.
        3) Use short task titles (1-4 words).
        4) Use visible emoji only.
        5) accentHex must be one of: \(defaultPalette.joined(separator: ", ")).
        """

        let session = LanguageModelSession(model: .default, instructions: instructions)

        do {
            let response = try await session.respond(
                to: """
                Session title: \(title)
                Total focus minutes: \(max(1, totalMinutes))
                Existing subtasks: [\(currentText)]
                """
            )
            return parseTasks(from: response.content, totalMinutes: totalMinutes)
        } catch {
            return nil
        }
    }

    private func parseTasks(from text: String, totalMinutes: Int) -> [FocusTask]? {
        SubtaskBreakdownTaskParser.parseTasks(
            from: text,
            totalMinutes: totalMinutes,
            defaultPalette: defaultPalette
        )
    }
}
#endif
