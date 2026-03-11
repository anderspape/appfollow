import Foundation

@MainActor
final class StatusBarNavigationBridge: ObservableObject {
    enum Command: Equatable {
        case openTimer
        case openSettings
    }

    @Published private(set) var commandVersion: Int = 0
    private(set) var latestCommand: Command = .openTimer

    func send(_ command: Command) {
        latestCommand = command
        commandVersion &+= 1
    }
}
