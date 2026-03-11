import Foundation

struct SuggestionRequestGate<Key: Hashable> {
    private var activeRequestTokens: [Key: UInt64] = [:]

    mutating func beginRequest(for key: Key) -> UInt64 {
        let nextToken = (activeRequestTokens[key] ?? 0) &+ 1
        activeRequestTokens[key] = nextToken
        return nextToken
    }

    mutating func invalidate(_ key: Key) {
        _ = beginRequest(for: key)
    }

    func isCurrent(_ token: UInt64, for key: Key) -> Bool {
        activeRequestTokens[key] == token
    }

    mutating func completeRequest(_ token: UInt64, for key: Key) {
        guard isCurrent(token, for: key) else { return }
        activeRequestTokens.removeValue(forKey: key)
    }
}
