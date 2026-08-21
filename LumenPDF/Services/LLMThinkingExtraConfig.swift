import Foundation

enum LLMThinkingExtraConfig {
    static func defaultJSON(baseURL: String, model: String) -> String {
        LLMExtraConfig.prettyPrinted(compactJSON(baseURL: baseURL, model: model))
    }

    static func compactJSON(baseURL: String, model: String) -> String {
        switch kind(baseURL: baseURL, model: model) {
        case .none:
            return ""
        case .enableThinking:
            return #"{"enable_thinking":false}"#
        case .chatTemplateKwargs:
            return #"{"chat_template_kwargs":{"enable_thinking":false}}"#
        case .thinkingType:
            return #"{"thinking":{"type":"disabled"}}"#
        case .openRouterReasoning:
            return #"{"reasoning":{"enabled":false}}"#
        }
    }

    private enum Kind {
        case none
        case enableThinking
        case chatTemplateKwargs
        case thinkingType
        case openRouterReasoning
    }

    private static func kind(baseURL: String, model: String) -> Kind {
        let host = host(of: baseURL)
        let qwen = isQwenFamily(model)

        if isOpenAI(host) || isGemini(host) {
            return .none
        }
        if isDashScope(host) || isSiliconFlow(host) {
            return .enableThinking
        }
        if isOpenRouter(host) {
            return .openRouterReasoning
        }
        if isZhipu(host) || isDeepSeek(host) || isVolcengine(host) {
            return .thinkingType
        }
        if qwen {
            return .chatTemplateKwargs
        }
        if isGLMFamily(model) || isDeepSeekFamily(model) {
            return .thinkingType
        }
        return .none
    }

    private static func host(of baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = trimmed
            .replacingOccurrences(of: "https://", with: "", options: [.anchored, .caseInsensitive])
            .replacingOccurrences(of: "http://", with: "", options: [.anchored, .caseInsensitive])
        let hostPart = withoutScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let afterAt = hostPart.split(separator: "@").last.map(String.init) ?? hostPart
        return afterAt.split(separator: ":").first.map(String.init)?.lowercased() ?? ""
    }

    private static func isQwenFamily(_ model: String) -> Bool {
        let model = model.lowercased()
        return model.contains("qwen") || model.contains("qwq") || model == "coder-model"
    }

    private static func isGLMFamily(_ model: String) -> Bool {
        let model = model.lowercased()
        return model.contains("glm") || model.contains("chatglm")
    }

    private static func isDeepSeekFamily(_ model: String) -> Bool {
        model.lowercased().contains("deepseek")
    }

    private static func isDashScope(_ host: String) -> Bool {
        host.contains("dashscope")
            || host.contains("bailian")
            || host.contains("alibaba-inc.com")
            || host.contains("aliyuncs.com")
            || host.contains("idealab")
    }

    private static func isSiliconFlow(_ host: String) -> Bool {
        host.contains("siliconflow")
    }

    private static func isOpenRouter(_ host: String) -> Bool {
        host.contains("openrouter.ai")
    }

    private static func isZhipu(_ host: String) -> Bool {
        host.contains("bigmodel.cn") || host.contains("api.z.ai") || host.hasSuffix(".z.ai")
    }

    private static func isDeepSeek(_ host: String) -> Bool {
        host == "api.deepseek.com" || host.hasSuffix(".deepseek.com")
    }

    private static func isVolcengine(_ host: String) -> Bool {
        host.contains("volces.com") || host.contains("volcengine")
    }

    private static func isOpenAI(_ host: String) -> Bool {
        host == "api.openai.com" || host.hasSuffix(".openai.com")
    }

    private static func isGemini(_ host: String) -> Bool {
        host.contains("generativelanguage.googleapis.com")
    }
}
