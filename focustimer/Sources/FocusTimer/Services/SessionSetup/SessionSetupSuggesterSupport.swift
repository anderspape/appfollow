import Foundation

func sanitizeEmoji(_ input: String, fallback: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let firstEmoji = trimmed.firstEmojiLike() {
        return firstEmoji
    }
    return fallback
}

enum SessionSetupDebug {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FOCUSTIMER_AI_DEBUG"] == "1"
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        FocusTimerDebugLog.ai(message)
    }
}
