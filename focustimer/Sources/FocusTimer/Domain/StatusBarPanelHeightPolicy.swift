import CoreGraphics

enum StatusBarPanelContext: Equatable {
    case timerMinified
    case timerFull(focusMusicEnabled: Bool)
    case nonTimer
}

enum StatusBarPanelHeightPolicy {
    static func preferredHeight(
        contentHeight: CGFloat,
        panelOuterPadding: CGFloat,
        contentVerticalPadding: CGFloat,
        context: StatusBarPanelContext
    ) -> CGFloat {
        switch context {
        case .timerMinified:
            return max(
                StatusBarLayout.minimumPanelHeight,
                contentHeight + (panelOuterPadding * 2)
            )

        case .timerFull(let focusMusicEnabled):
            let reservedTimerHeight = focusMusicEnabled
                ? StatusBarLayout.timerFullHeightWhenMusicExpanded
                : StatusBarLayout.timerFullHeightWithoutMusic
            return max(reservedTimerHeight, contentHeight + contentVerticalPadding)

        case .nonTimer:
            let minimumHeight = StatusBarLayout.screenMinimumContentHeight + contentVerticalPadding
            return max(
                StatusBarLayout.absoluteMinimumPanelHeight,
                minimumHeight,
                contentHeight + contentVerticalPadding
            )
        }
    }
}
