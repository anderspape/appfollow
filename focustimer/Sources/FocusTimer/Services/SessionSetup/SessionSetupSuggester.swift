import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SessionSetupSuggestion: Codable, Equatable {
    var title: String
    var emoji: String
    var focusMinutes: Int
    var accentHex: String
}

protocol SessionSetupSuggesting {
    func suggest(from prompt: String, current: SessionSetupSuggestion) async -> SessionSetupSuggestion?
}


struct SessionSetupSuggester: SessionSetupSuggesting {
    func suggest(from prompt: String, current: SessionSetupSuggestion) async -> SessionSetupSuggestion? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        SessionSetupDebug.log("Request received: \"\(trimmedPrompt)\"")

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let modelAvailable = SystemLanguageModel.default.isAvailable
                SessionSetupDebug.log("FoundationModels compiled in. Runtime available: \(modelAvailable)")

                if modelAvailable,
                   let modelSuggestion = await FoundationModelSessionSetupSuggester().suggest(from: prompt, current: current)
                {
                    SessionSetupDebug.log("Using Foundation Model output")
                    return modelSuggestion
                }
            } else {
                SessionSetupDebug.log("macOS < 26.0. Foundation Model path unavailable.")
            }
        #else
            SessionSetupDebug.log("FoundationModels module not available at compile time.")
        #endif

        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct FoundationModelSessionSetupSuggester {
    private struct ModelSuggestionPayload: Codable {
        var title: String
        var emoji: String
        var focusMinutes: Int
        var accentHex: String
        var category: String?
    }

    func suggest(from prompt: String, current: SessionSetupSuggestion) async -> SessionSetupSuggestion? {
        let currentJSON: String
        if let data = try? JSONEncoder().encode(current), let text = String(data: data, encoding: .utf8) {
            currentJSON = text
        } else {
            currentJSON = "{\"title\":\"Do Laundry\",\"emoji\":\"🧺\",\"focusMinutes\":25,\"accentHex\":\"#9E84FF\"}"
        }

        let instructions = """
        You are a focus timer setup assistant for macOS.
        You must return ONLY valid minified JSON with this schema:
        {"title":"string","emoji":"single emoji","focusMinutes":1...180,"accentHex":"#RRGGBB","category":"one of allowed categories"}
        No markdown. No extra keys.

        Behavior rules:
        1) If user implies a task type, set a category and choose a task-relevant emoji.
        2) Always choose accentHex from this category palette:
        \(categoryGuide)
        3) focusMinutes guidance:
           - Work/Study/Deep work: 35-50
           - Admin/Errands/Household: 15-30
           - Self care/Health/Human needs: 10-25
           - Breaks: 5-25
        4) If user gives an explicit duration, always respect it (1...180).
        5) Emoji must be a standard visible emoji character.
        6) Do not return icon glyphs such as SF Symbols pseudo-characters.
        7) If uncertain, keep title but still choose a valid category with matching emoji and color.
        """

        let session = LanguageModelSession(model: .default, instructions: instructions)

        do {
            SessionSetupDebug.log("Calling Foundation Model…")
            let response = try await session.respond(
                to: """
                Current settings: \(currentJSON)
                User request: \(prompt)
                """
            )
            SessionSetupDebug.log("Raw model response: \(response.content)")
            let parsed = parseSuggestion(from: response.content, prompt: prompt, fallback: current)
            if parsed == nil {
                SessionSetupDebug.log("Foundation Model responded, but parsing failed.")
            }
            return parsed
        } catch {
            SessionSetupDebug.log("Foundation Model call failed: \(error.localizedDescription)")
            return nil
        }
    }

    private var categoryGuide: String {
        SessionCategory.all
            .map { "\($0.name)=\($0.colorHex)" }
            .joined(separator: ", ")
    }

    private func parseSuggestion(from text: String, prompt: String, fallback: SessionSetupSuggestion) -> SessionSetupSuggestion? {
        guard let json = extractJSONObject(from: text),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ModelSuggestionPayload.self, from: data)
        else {
            return nil
        }

        SessionSetupDebug.log(
            """
            Decoded model payload: title="\(decoded.title)" emoji="\(decoded.emoji)" \
            focusMinutes=\(decoded.focusMinutes) accentHex="\(decoded.accentHex)" category="\(decoded.category ?? "nil")"
            """
        )

        let category = resolveCategory(from: decoded, prompt: prompt)
        if let category {
            SessionSetupDebug.log("Resolved category: \(category.name)")
        } else {
            SessionSetupDebug.log("Resolved category: none")
        }
        let sanitizedTitle = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = sanitizedTitle.isEmpty ? fallback.title : sanitizedTitle

        let explicitPromptEmoji = prompt.firstEmojiLike()
        let emoji: String
        if let explicitPromptEmoji {
            emoji = explicitPromptEmoji
        } else {
            emoji = sanitizeEmoji(decoded.emoji, fallback: fallback.emoji)
        }
        let focusMinutes = normalizedFocusMinutes(
            modelMinutes: decoded.focusMinutes,
            prompt: prompt,
            category: category,
            fallback: fallback.focusMinutes
        )

        let accentHex: String
        if let explicitHex = parseExplicitHexColor(prompt) {
            accentHex = explicitHex
        } else if let category {
            accentHex = category.colorHex
        } else if let normalized = HexColor.normalize(decoded.accentHex),
                  SessionCategory.colorPaletteHexes.contains(normalized)
        {
            accentHex = normalized
        } else {
            accentHex = fallback.accentHex
        }

        SessionSetupDebug.log("Normalized output title=\"\(title)\" minutes=\(focusMinutes) emoji=\(emoji) color=\(accentHex)")
        return SessionSetupSuggestion(
            title: title,
            emoji: emoji,
            focusMinutes: focusMinutes,
            accentHex: accentHex
        )
    }

    private func resolveCategory(from decoded: ModelSuggestionPayload, prompt: String) -> SessionCategory? {
        // Prefer user prompt intent over model category to keep live typing deterministic.
        if let promptCategory = SessionCategory.match(in: prompt) {
            return promptCategory
        }

        if let raw = decoded.category?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            if let byName = SessionCategory.all.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame }) {
                return byName
            }
        }

        let sourceText = "\(prompt) \(decoded.title)"
        return SessionCategory.match(in: sourceText)
    }

    private func normalizedFocusMinutes(
        modelMinutes: Int,
        prompt: String,
        category: SessionCategory?,
        fallback: Int
    ) -> Int {
        if let explicit = parseExplicitDuration(prompt) {
            return explicit
        }

        let clamped = min(180, max(1, modelMinutes))
        guard let category else { return clamped }

        if clamped == fallback {
            return category.recommendedFocusMinutes
        }
        if category.recommendedRange.contains(clamped) {
            return clamped
        }
        return category.recommendedFocusMinutes
    }

    private func parseExplicitDuration(_ prompt: String) -> Int? {
        if let minutesMatch = prompt.firstMatch(of: #/(\d{1,3})\s*(?:m|min|mins|minute|minutes)\b/#),
           let minutes = Int(minutesMatch.1)
        {
            return min(180, max(1, minutes))
        }

        if let hoursMatch = prompt.firstMatch(of: #/(\d{1,2})\s*(?:h|hr|hour|hours)\b/#),
           let hours = Int(hoursMatch.1)
        {
            return min(180, max(1, hours * 60))
        }

        return nil
    }

    private func parseExplicitHexColor(_ prompt: String) -> String? {
        if let match = prompt.firstMatch(of: #/#([A-Fa-f0-9]{3}|[A-Fa-f0-9]{6})\b/#) {
            return HexColor.normalize("#\(match.1)")
        }
        return nil
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}")
        else {
            return nil
        }
        return String(text[first...last])
    }
}
#endif
