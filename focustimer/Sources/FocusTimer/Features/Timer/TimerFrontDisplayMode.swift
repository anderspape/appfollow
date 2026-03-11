import Foundation

enum TimerFrontDisplayMode: String, CaseIterable {
    case full
    case minified

    static let storageKey = "focus_timer.ui.front_display_mode.v1"

    static func fromStoredValue(_ value: String?) -> Self {
        guard let value, let mode = Self(rawValue: value) else {
            return .full
        }
        return mode
    }
}
