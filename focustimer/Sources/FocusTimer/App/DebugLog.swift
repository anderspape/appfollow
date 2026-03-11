import Foundation

enum FocusTimerDebugLog {
    private static let isEnabled = ProcessInfo.processInfo.environment["FOCUSTIMER_AI_LOG"] == "1"
    private static let queue = DispatchQueue(label: "FocusTimerDebugLog.queue")
    private static let aiLogURL = URL(fileURLWithPath: "/tmp/focustimer-ai.log")

    static func ai(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let resolvedMessage = message()
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(timestamp) [SessionSetupAI] \(resolvedMessage)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: aiLogURL.path) {
                if let handle = try? FileHandle(forWritingTo: aiLogURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: aiLogURL, options: .atomic)
            }
        }
    }
}
