import Foundation
import AVFoundation

final class TaskCompletionSoundPlayer {
    static let shared = TaskCompletionSoundPlayer()

    private var player: AVAudioPlayer?
    private let preferredSoundName = "slowNotification"
    private let fallbackSoundName = "done_sound"

    private init() {
        prepareIfNeeded()
    }

    func play() {
        prepareIfNeeded()
        guard let player else { return }

        if player.isPlaying {
            player.stop()
        }
        player.currentTime = 0
        player.play()
    }

    private func prepareIfNeeded() {
        guard player == nil else { return }

        let url =
            Bundle.module.url(forResource: preferredSoundName, withExtension: "wav")
            ?? Bundle.module.url(forResource: fallbackSoundName, withExtension: "wav")

        guard let url else {
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.volume = 1.0
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            return
        }
    }
}
