import SwiftUI

struct StatusBarTimerTheme {
    let colorScheme: ColorScheme

    let panelWidth: CGFloat = StatusBarLayout.panelWidth
    let innerCardCornerRadius: CGFloat = 12
    let panelInnerPadding: CGFloat = 12

    var cardCornerRadius: CGFloat { innerCardCornerRadius }
    var panelCornerRadius: CGFloat { innerCardCornerRadius + panelInnerPadding }

    var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.black.opacity(0.92)
    }

    var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.62)
    }

    var settingsCardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.3)
    }

    var settingsPillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.055)
    }

    var settingsDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.05)
    }

    var taskCardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.40)
    }

    var taskCardStrokeColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34)
    }

    var taskCardHoverStrokeColor: Color {
        Color(red: 0.62, green: 0.52, blue: 1.0)
            .opacity(colorScheme == .dark ? 0.86 : 0.74)
    }

    var ringTrackColor: Color {
        Color(red: 0.87, green: 0.89, blue: 1.0)
    }

    var ringProgressColor: Color {
        Color(red: 0.62, green: 0.52, blue: 1.0)
    }

    var playPauseBackgroundColor: Color {
        Color(red: 0.09, green: 0.07, blue: 0.07)
    }

    var favoriteAccentColor: Color {
        Color(red: 0.96, green: 0.34, blue: 0.44)
    }
}
