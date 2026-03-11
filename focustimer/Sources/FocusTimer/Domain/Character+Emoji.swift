import Foundation

extension Character {
    var isEmojiLike: Bool {
        // Exclude plain ASCII characters (e.g. digits in "25m") from emoji detection.
        if unicodeScalars.allSatisfy(\.isASCII) {
            return false
        }

        // Standard single-scalar emoji presentation.
        if unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
            return true
        }

        // Multi-scalar clusters such as keycaps or ZWJ emoji sequences.
        if unicodeScalars.count > 1, unicodeScalars.contains(where: { $0.properties.isEmoji }) {
            return true
        }

        return false
    }
}

extension String {
    func firstEmojiLike() -> String? {
        first(where: \.isEmojiLike).map(String.init)
    }
}
