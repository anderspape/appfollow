import SwiftUI
import AppKit

@MainActor
final class StatusBarPanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private enum Layout {
        static let panelWidth: CGFloat = StatusBarLayout.panelWidth
        static let defaultInitialHeight: CGFloat = 478
        static let minimumPanelHeight: CGFloat = StatusBarLayout.minimumPanelHeight
        static let initialSize = NSSize(width: panelWidth, height: defaultInitialHeight)
        static let minContentSize = NSSize(width: panelWidth, height: minimumPanelHeight)
        static let defaultTrailingInset: CGFloat = 26
        static let defaultTopInset: CGFloat = 34
    }

    private let viewModel: TimerViewModel
    private let taskLibraryStore: TaskLibraryStore
    private let navigationBridge = StatusBarNavigationBridge()
    private var panel: NSPanel?
    private let frameAutosaveName = "FocusTimerStatusBarPanelFrame"
    private var lastAppliedContentSize: NSSize?
    private var pendingPreferredContentSize: CGSize?

    init(
        viewModel: TimerViewModel,
        taskLibraryStore: TaskLibraryStore
    ) {
        self.viewModel = viewModel
        self.taskLibraryStore = taskLibraryStore
        super.init()

        DispatchQueue.main.async { [weak self] in
            self?.show()
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = ensurePanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
    }

    func showSettings() {
        show()
        navigationBridge.send(.openSettings)
    }

    func showTimer() {
        show()
        navigationBridge.send(.openTimer)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func resetPosition() {
        let panel = ensurePanel()
        positionAtDefaultOrigin(panel)
        panel.saveFrame(usingName: frameAutosaveName)
        show()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let contentView = NSHostingView(
            rootView: StatusBarTimerView(
                viewModel: viewModel,
                navigationBridge: navigationBridge,
                taskLibraryStore: taskLibraryStore,
                onPreferredSizeChange: { [weak self] size in
                    self?.updatePanelSizeIfNeeded(size)
                },
                onSettingsVisibilityChange: { [weak self] isShowingSettings in
                    self?.panel?.isMovableByWindowBackground = !isShowingSettings
                }
            )
            .ignoresSafeArea(.all)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Layout.initialSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure(panel: panel, contentView: contentView)

        if !panel.setFrameUsingName(frameAutosaveName, force: false) {
            positionAtDefaultOrigin(panel)
        }

        self.panel = panel
        if let pendingPreferredContentSize {
            updatePanelSizeIfNeeded(pendingPreferredContentSize)
            self.pendingPreferredContentSize = nil
        }
        return panel
    }

    private func updatePanelSizeIfNeeded(_ size: CGSize) {
        guard let panel else {
            pendingPreferredContentSize = size
            return
        }

        let requested = NSSize(
            width: max(Layout.minContentSize.width, size.width),
            height: max(Layout.minContentSize.height, size.height)
        )

        if let lastAppliedContentSize,
           abs(lastAppliedContentSize.width - requested.width) < 0.5,
           abs(lastAppliedContentSize.height - requested.height) < 0.5
        {
            return
        }

        let oldFrame = panel.frame
        panel.setContentSize(requested)
        let newFrame = panel.frame

        let adjustedOrigin = NSPoint(
            x: oldFrame.minX,
            y: oldFrame.maxY - newFrame.height
        )
        panel.setFrameOrigin(adjustedOrigin)

        lastAppliedContentSize = requested
        panel.saveFrame(usingName: frameAutosaveName)
    }

    private func positionAtDefaultOrigin(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let x = screenFrame.maxX - panel.frame.width - Layout.defaultTrailingInset
        let y = screenFrame.maxY - panel.frame.height - Layout.defaultTopInset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func configure(panel: NSPanel, contentView: NSView) {
        panel.contentView = contentView
        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName(frameAutosaveName)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        isVisible = true
    }

    func windowDidResignKey(_ notification: Notification) {
        isVisible = panel?.isVisible ?? false
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
}
