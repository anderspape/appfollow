import Foundation

@MainActor
final class SuggestionTaskBag {
    enum Key: Hashable {
        case live
        case subtask(UUID)
    }

    private var tasks: [Key: Task<Void, Never>] = [:]

    func replace(_ task: Task<Void, Never>, for key: Key) {
        tasks[key]?.cancel()
        tasks[key] = task
    }

    func cancel(_ key: Key) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }

    func remove(_ key: Key) {
        tasks.removeValue(forKey: key)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    var subtaskTaskIDs: [UUID] {
        tasks.keys.compactMap { key in
            if case .subtask(let taskID) = key {
                return taskID
            }
            return nil
        }
    }
}
