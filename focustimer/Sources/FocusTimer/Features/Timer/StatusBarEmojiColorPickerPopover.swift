import SwiftUI
import EmojiKit

struct StatusBarEmojiColorPickerPopover: View {
    @Binding var emoji: String
    @Binding var accentHex: String
    @Binding var emojiCategory: EmojiCategory?
    @Binding var emojiSelection: Emoji.GridSelection?

    let fallbackColor: Color
    let categoryColorHexes: [String]
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let dividerColor: Color

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentHex) ?? fallbackColor },
            set: { newColor in
                if let normalized = newColor.hexString {
                    accentHex = normalized
                }
            }
        )
    }

    private var normalizedAccentHex: String {
        HexColor.normalize(accentHex) ?? accentHex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Emoji & color")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(secondaryTextColor)

            Text("Emoji")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondaryTextColor.opacity(0.9))

            EmojiGridScrollView(
                axis: .vertical,
                categories: .standardGrid,
                category: $emojiCategory,
                selection: $emojiSelection,
                action: { selectedEmoji in
                    emoji = selectedEmoji.char
                },
                sectionTitle: { $0.view },
                gridItem: { $0.view }
            )
            .emojiGridStyle(.init(fontSize: 22, itemSpacing: 4, padding: 6, sectionSpacing: 10))
            .frame(height: 220)

            Divider()
                .overlay(dividerColor)

            Text("Presets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondaryTextColor.opacity(0.9))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6), spacing: 8) {
                ForEach(categoryColorHexes, id: \.self) { hex in
                    Button {
                        accentHex = hex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex) ?? fallbackColor)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )

                            if normalizedAccentHex == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .statusBarHoverEffect()
                }
            }

            Divider()
                .overlay(dividerColor)

            HStack(spacing: 10) {
                Circle()
                    .fill(accentColorBinding.wrappedValue)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )

                Text(normalizedAccentHex)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primaryTextColor)

                Spacer(minLength: 0)

                ColorPicker("Custom", selection: accentColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 18)
            }
        }
        .padding(12)
        .frame(width: 284)
    }
}
