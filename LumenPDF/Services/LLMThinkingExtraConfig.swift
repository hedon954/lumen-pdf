import Foundation

enum LLMThinkingExtraConfig {
    /// Settings display copy of the Rust provider default. Pretty-printed only
    /// for the editor; the compact JSON from UniFFI is what HTTP merge uses.
    static func defaultJSON(baseURL: String, model: String) -> String {
        LLMExtraConfig.prettyPrinted(BridgeService.defaultExtraConfig(baseURL: baseURL, model: model))
    }
}
