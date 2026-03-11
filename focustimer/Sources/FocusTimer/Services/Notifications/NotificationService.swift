import Foundation
import UserNotifications

protocol NotificationServicing {
    func requestAuthorizationIfNeeded()
    func notifyPhaseChange(phase: SessionPhase, minutes: Int)
}

struct NotificationService: NotificationServicing {
    private var canUseSystemNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorizationIfNeeded() {
        guard canUseSystemNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyPhaseChange(phase: SessionPhase, minutes: Int) {
        guard canUseSystemNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "Fokustid startet" : "Pause startet"
        content.body = phase == .focus
            ? "Ny fokusrunde på \(minutes) minutter."
            : "Tag en pause på \(minutes) minutter."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
