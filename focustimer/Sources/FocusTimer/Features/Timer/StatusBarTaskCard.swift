import SwiftUI

struct StatusBarTaskCard<Leading: View, Trailing: View>: View {
    let theme: StatusBarTimerTheme
    let title: String
    let subtitle: String
    let onTap: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryTextColor.opacity(0.96))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .statusBarHoverEffect()
        .background(
            RoundedRectangle(cornerRadius: theme.innerCardCornerRadius, style: .continuous)
                .fill(theme.taskCardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.innerCardCornerRadius, style: .continuous)
                        .stroke(theme.taskCardStrokeColor, lineWidth: 0.8)
                )
        )
    }
}
