import Foundation

enum LLMProviderPickerSelection: Equatable {
    case builtIn(LLMProviderPreset)
    case other

    static let otherTag = "other"
    static let otherTitle = "其他"

    var tag: String {
        switch self {
        case let .builtIn(provider):
            return "provider:\(provider.id)"
        case .other:
            return Self.otherTag
        }
    }

    static func resolved(baseURL: String, preferOther: Bool = false) -> Self {
        if preferOther {
            return .other
        }
        if let provider = LLMProviderPreset.matching(baseURL: baseURL) {
            return .builtIn(provider)
        }
        return .other
    }

    static func builtInPreset(id: String) -> LLMProviderPreset? {
        LLMProviderPreset.builtIn.first { $0.id == id }
    }

    /// Choosing 「其他」 never applies a built-in preset.
    /// If the current URL is already unmatched, keep it.
    /// Switching back restores the last unmatched URL instead of clobbering it.
    static func restoredCustomBaseURL(
        currentBaseURL: String,
        lastCustomBaseURL: String
    ) -> String? {
        if LLMProviderPreset.matching(baseURL: currentBaseURL) == nil {
            return nil
        }
        let trimmed = lastCustomBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              LLMProviderPreset.matching(baseURL: trimmed) == nil
        else {
            return nil
        }
        return trimmed
    }
}
