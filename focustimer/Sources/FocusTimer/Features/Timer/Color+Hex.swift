import SwiftUI
import AppKit

extension Color {
    init?(hex: String) {
        guard let normalized = HexColor.normalize(hex) else { return nil }
        let value = String(normalized.dropFirst())
        guard let rgb = Int(value, radix: 16) else { return nil }

        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }

        let red = min(255, max(0, Int((rgb.redComponent * 255).rounded())))
        let green = min(255, max(0, Int((rgb.greenComponent * 255).rounded())))
        let blue = min(255, max(0, Int((rgb.blueComponent * 255).rounded())))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
