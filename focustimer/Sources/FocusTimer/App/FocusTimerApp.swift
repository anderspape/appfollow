import SwiftUI
import AppKit

@main
struct FocusTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: TimerViewModel
    @StateObject private var panelController: StatusBarPanelController

    init() {
        FontRegistrar.registerIfNeeded()

        let settingsStore = SettingsStore()
        let taskLibraryStore = TaskLibraryStore()
        let notificationService = NotificationService()
        let activitiesService = ActivitiesService()
        let todayViewModel = TodayViewModel(
            activitiesService: activitiesService,
            profileID: TiimoActivitiesConfiguration.default.profileID
        )
        let timerViewModel = TimerViewModel(
            settingsStore: settingsStore,
            notificationService: notificationService
        )
        _viewModel = StateObject(
            wrappedValue: timerViewModel
        )
        _panelController = StateObject(
            wrappedValue: StatusBarPanelController(
                viewModel: timerViewModel,
                todayViewModel: todayViewModel,
                taskLibraryStore: taskLibraryStore
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            Button(panelController.isVisible ? "Hide timer" : "Show timer") {
                panelController.toggle()
            }

            Button("Settings") {
                panelController.showSettings()
            }

            Button("Reset timer position") {
                panelController.resetPosition()
            }

            Button("Send feedback") {
                openFeedbackEmail()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: viewModel.isRunning ? "pause.circle.fill" : "play.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)
    }

    private func openFeedbackEmail() {
        guard let url = URL(string: "mailto:info@tiimo.dk?subject=Tiimo%20Focus%20Feedback") else {
            return
        }
        _ = NSWorkspace.shared.open(url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
