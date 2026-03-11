import SwiftUI
import Lottie

struct StatusBarTaskConfettiOverlay: NSViewRepresentable {
    private static let primaryAnimationName = "ConfettiExplode"
    private static let fallbackAnimationName = "TiimoConfetti"

    let trigger: Int
    let onPlaybackFinished: () -> Void

    init(trigger: Int, onPlaybackFinished: @escaping () -> Void = {}) {
        self.trigger = trigger
        self.onPlaybackFinished = onPlaybackFinished
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastTrigger: .min, onPlaybackFinished: onPlaybackFinished)
    }

    func makeNSView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.animation =
            LottieAnimation.named(Self.primaryAnimationName, bundle: .module)
            ?? LottieAnimation.named(Self.fallbackAnimationName, bundle: .module)
        view.loopMode = .playOnce
        view.contentMode = .scaleAspectFill
        view.backgroundBehavior = .pauseAndRestore
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        return view
    }

    func updateNSView(_ nsView: LottieAnimationView, context: Context) {
        context.coordinator.onPlaybackFinished = onPlaybackFinished

        guard trigger != context.coordinator.lastTrigger else { return }
        context.coordinator.lastTrigger = trigger

        guard nsView.animation != nil else {
            context.coordinator.finishPlayback()
            return
        }

        nsView.stop()
        nsView.currentProgress = 0
        nsView.play { _ in
            context.coordinator.finishPlayback()
        }
    }

    final class Coordinator {
        var lastTrigger: Int
        var onPlaybackFinished: () -> Void

        init(lastTrigger: Int, onPlaybackFinished: @escaping () -> Void) {
            self.lastTrigger = lastTrigger
            self.onPlaybackFinished = onPlaybackFinished
        }

        func finishPlayback() {
            DispatchQueue.main.async {
                self.onPlaybackFinished()
            }
        }
    }
}
