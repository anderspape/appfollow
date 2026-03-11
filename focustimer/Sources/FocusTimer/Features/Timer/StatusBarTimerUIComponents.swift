import SwiftUI

struct StatusBarHoverEffectModifier: ViewModifier {
    let enabled: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled && isHovered ? 1.0 : 1.01)
            .opacity(enabled && isHovered ? 0.96 : 1.0)
            .offset(y: enabled && isHovered ? -0.5 : 0)
            .animation(.easeInOut(duration: 0.25), value: isHovered)
            .onHover { hovering in
                guard enabled else { return }
                isHovered = hovering
            }
    }
}

extension View {
    func statusBarHoverEffect(enabled: Bool = true) -> some View {
        modifier(StatusBarHoverEffectModifier(enabled: enabled))
    }
}

struct StatusBarToolbarButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect()
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Circle())
        .background(
            Circle()
                .fill(.ultraThickMaterial.opacity(isHovered ? 1 : 0))
        )
    }
}

struct StatusBarSaveToolbarButton: View {
    let isSaving: Bool
    let accentColor: Color
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(width: 34, height: 34)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect(enabled: !isSaving)
        .contentShape(Circle())
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.7 : 0.82))
                )
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.45), lineWidth: 0.8)
        )
    }
}

struct StatusBarAccentToolbarButton: View {
    let systemName: String
    let accentColor: Color
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect()
        .contentShape(Circle())
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.68 : 0.82))
                )
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.45), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.11), radius: 8, y: 3)
    }
}

struct StatusBarSettingsRow<Control: View>: View {
    let label: String
    let labelColor: Color
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(labelColor)

            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct StatusBarValuePill<Content: View>: View {
    let backgroundColor: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor, in: Capsule())
    }
}

struct StatusBarSubtasksHeaderButton<Label: View>: View {
    let foreground: Color
    let background: Color
    let colorScheme: ColorScheme
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(background, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect()
    }
}

struct StatusBarDivider: View {
    let color: Color

    var body: some View {
        Divider()
            .overlay(color.opacity(0.1))
    }
}
