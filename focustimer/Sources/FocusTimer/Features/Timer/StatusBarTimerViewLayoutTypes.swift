import SwiftUI

enum StatusBarTimerScreen: Int {
    case library = 0
    case timer = 1
    case today = 2
    case settings = 3
    case editTask = 4
}

enum StatusBarTimerScreenTransitionDirection {
    case toLeading
    case toTrailing

    var insertionEdge: Edge {
        switch self {
        case .toLeading: return .leading
        case .toTrailing: return .trailing
        }
    }

    var removalEdge: Edge {
        switch self {
        case .toLeading: return .trailing
        case .toTrailing: return .leading
        }
    }
}

enum StatusBarTimerMeasuredView {
    case timer
    case today
    case settings
    case editTask
    case library
}

enum StatusBarTimerLayoutMetrics {
    static func estimatedInitialTimerContentHeight(taskCount: Int) -> CGFloat {
        let normalizedTaskCount = max(0, taskCount)
        let baseContentHeight: CGFloat = 408
        guard normalizedTaskCount > 0 else { return baseContentHeight }

        let rowHeight: CGFloat = 39
        let rowSpacing: CGFloat = 8
        let sectionPadding: CGFloat = 14
        let totalRowsHeight = CGFloat(normalizedTaskCount) * rowHeight
        let totalSpacingHeight = CGFloat(max(0, normalizedTaskCount - 1)) * rowSpacing
        return baseContentHeight + sectionPadding + totalRowsHeight + totalSpacingHeight
    }
}
