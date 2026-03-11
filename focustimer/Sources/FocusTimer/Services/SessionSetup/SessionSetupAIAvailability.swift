import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SessionSetupAIStatus {
    let isAvailable: Bool
    let title: String
    let detail: String
}

enum SessionSetupAIAvailability {
    static var currentStatus: SessionSetupAIStatus {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if SystemLanguageModel.default.isAvailable {
                    return SessionSetupAIStatus(
                        isAvailable: true,
                        title: "AI model is active",
                        detail: "AI is available on this device and is powered by Apple Intelligence."
                    )
                }
                return SessionSetupAIStatus(
                    isAvailable: false,
                    title: "AI model unavailable",
                    detail: "Apple Intelligence is not ready yet (language, setup, or download)."
                )
            }
            return SessionSetupAIStatus(
                isAvailable: false,
                title: "AI model unavailable",
                detail: "Requires macOS 26 or newer."
            )
        #else
            return SessionSetupAIStatus(
                isAvailable: false,
                title: "AI model unavailable",
                detail: "FoundationModels is not included in this build."
            )
        #endif
    }
}
