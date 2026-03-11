import SwiftUI

struct StatusBarGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 16
    var clipContent: Bool = true

    private var borderStrokeColor: Color {
        Color.white.opacity(0.18)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                let base = GlassEffectContainer {
                    content
                }
                .glassEffect(.tint(Glass), in: shape)

                if clipContent {
                    base
                        .clipShape(shape)
                        .overlay(
                            shape
                                .stroke(borderStrokeColor, lineWidth: 0.8)
                        )
                } else {
                    base
                        .overlay(
                            shape
                                .stroke(borderStrokeColor, lineWidth: 0.8)
                        )
                }
            } else {
                content
                    .background(.regularMaterial, in: shape)
                    .overlay(
                        shape
                            .stroke(borderStrokeColor, lineWidth: 0.8)
                    )
            }
        #else
            content
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape
                        .stroke(borderStrokeColor, lineWidth: 0.8)
                )
        #endif
    }
}

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ViewSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ViewSizePreferenceKey.self, perform: onChange)
    }
}
