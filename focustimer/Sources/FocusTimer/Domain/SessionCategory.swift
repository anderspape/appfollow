import Foundation

struct SessionCategory: Equatable {
    let name: String
    let colorHex: String
    let emoji: String
    let keywords: [String]
}

extension SessionCategory {
    static let all: [SessionCategory] = [
        SessionCategory(name: "Household", colorHex: "#A9D1D6", emoji: "🧺", keywords: ["household", "home", "laundry", "clean", "kitchen", "chores", "groceries", "shopping", "errands", "vasketøj", "indkøb", "husholdning", "rengøring"]),
        SessionCategory(name: "Relationship", colorHex: "#E5C2E1", emoji: "💞", keywords: ["relationship", "partner", "family", "friends", "date", "kæreste", "familie", "venner"]),
        SessionCategory(name: "Human needs", colorHex: "#B0A2CF", emoji: "🍽️", keywords: ["human needs", "food", "eat", "drink", "sleep", "meal", "mad", "søvn"]),
        SessionCategory(name: "Social", colorHex: "#B8C5EF", emoji: "💬", keywords: ["social", "call", "chat", "community", "network", "snak"]),
        SessionCategory(name: "Admin", colorHex: "#6A66DA", emoji: "🗂️", keywords: ["admin", "paperwork", "forms", "inbox", "budget", "plan", "todo", "emails", "calendar", "økonomi"]),
        SessionCategory(name: "Hobby", colorHex: "#C95F76", emoji: "🎨", keywords: ["hobby", "music", "guitar", "drawing", "craft", "creative", "photo", "gaming"]),
        SessionCategory(name: "Breaks", colorHex: "#4A89AE", emoji: "☕", keywords: ["break", "pause", "walk", "stretch", "reset", "mind break", "screen break", "coffee", "tea", "exercise", "workout", "gym", "run", "cardio", "strength", "træning", "løb"]),
        SessionCategory(name: "Self care", colorHex: "#CEE281", emoji: "🧘", keywords: ["self care", "selfcare", "meditate", "mindfulness", "rest", "journal", "spa", "egenomsorg", "yoga"]),
        SessionCategory(name: "Health", colorHex: "#DFDBBA", emoji: "🩺", keywords: ["health", "doctor", "medicine", "meds", "appointment", "therapy", "wellness", "sundhed"]),
        SessionCategory(name: "Pets", colorHex: "#0D6F73", emoji: "🐾", keywords: ["pets", "pet", "dog", "cat", "walk dog", "fodre", "dyr"]),
        SessionCategory(name: "Work", colorHex: "#89BDD0", emoji: "💼", keywords: ["work", "meeting", "office", "career", "project", "client", "job", "arbejde"]),
        SessionCategory(name: "Study", colorHex: "#8A7BE9", emoji: "📚", keywords: ["study", "school", "homework", "exam", "learn", "reading", "college", "uni", "studie"]),
    ]

    private static let legacyNameAliases: [String: String] = [
        "exercise": "Breaks"
    ]

    static let colorPaletteHexes: [String] = all.map(\.colorHex)

    static let emojiPalette: [String] = all.map(\.emoji)

    static func named(_ name: String) -> SessionCategory? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let canonical = legacyNameAliases[normalized]?.lowercased() ?? normalized
        return all.first { $0.name.lowercased() == canonical }
    }

    static func match(colorHex: String) -> SessionCategory? {
        guard let normalized = HexColor.normalize(colorHex) else { return nil }
        return all.first { $0.colorHex == normalized }
    }

    static func match(in text: String) -> SessionCategory? {
        let lowercased = text.lowercased()
        return all.first { category in
            category.keywords.contains(where: { lowercased.contains($0) })
        }
    }

    var recommendedFocusMinutes: Int {
        switch name {
        case "Work", "Study":
            return 40
        case "Admin", "Household":
            return 25
        case "Self care", "Health", "Human needs":
            return 20
        case "Breaks":
            return 15
        case "Hobby", "Social", "Relationship", "Pets":
            return 25
        default:
            return 25
        }
    }

    var recommendedRange: ClosedRange<Int> {
        switch name {
        case "Work", "Study":
            return 35...50
        case "Admin", "Household":
            return 15...30
        case "Self care", "Health", "Human needs":
            return 10...25
        case "Breaks":
            return 5...25
        case "Hobby", "Social", "Relationship", "Pets":
            return 15...35
        default:
            return 10...45
        }
    }
}
