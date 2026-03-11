import CoreText
import Foundation

enum FontRegistrar {
    private static var hasRegistered = false

    static func registerIfNeeded() {
        guard !hasRegistered else { return }
        hasRegistered = true

        guard let url = Bundle.module.url(
            forResource: "Recoleta Regular",
            withExtension: "otf",
            subdirectory: "Fonts"
        ) else { return }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
