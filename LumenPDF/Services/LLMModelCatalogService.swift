import Foundation

struct LLMProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let supportedModelPrefixes: [String]?
    let compatibilityNote: String?

    init(
        id: String,
        name: String,
        baseURL: String,
        supportedModelPrefixes: [String]? = nil,
        compatibilityNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.supportedModelPrefixes = supportedModelPrefixes
        self.compatibilityNote = compatibilityNote
    }

    static let builtIn: [LLMProviderPreset] = [
        LLMProviderPreset(
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1"
        ),
        LLMProviderPreset(
            id: "aliyun-cn",
            name: "阿里云百炼（北京）",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        ),
        LLMProviderPreset(
            id: "aliyun-intl",
            name: "阿里云百炼（新加坡）",
            baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        ),
        LLMProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1"
        ),
        LLMProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1"
        ),
        LLMProviderPreset(
            id: "opencode-zen",
            name: "OpenCode Zen",
            baseURL: "https://opencode.ai/zen/v1",
            supportedModelPrefixes: [
                "big-pickle",
                "deepseek-",
                "glm-",
                "hy3-",
                "kimi-",
                "laguna-",
                "ling-",
                "mimo-",
                "minimax-",
                "nemotron-"
            ],
            compatibilityNote: "OpenCode Zen 同时提供多种 API 协议；这里仅展示 LumenPDF 当前支持的 Chat Completions 模型。"
        ),
        LLMProviderPreset(
            id: "gemini",
            name: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai"
        ),
        LLMProviderPreset(
            id: "siliconflow",
            name: "硅基流动",
            baseURL: "https://api.siliconflow.cn/v1"
        ),
        LLMProviderPreset(
            id: "zhipu",
            name: "智谱开放平台",
            baseURL: "https://open.bigmodel.cn/api/paas/v4"
        ),
        LLMProviderPreset(
            id: "minimax-cn",
            name: "MiniMax（中国）",
            baseURL: "https://api.minimaxi.com/v1"
        ),
        LLMProviderPreset(
            id: "volcengine",
            name: "火山方舟",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3"
        )
    ]

    static func matching(baseURL: String) -> LLMProviderPreset? {
        let key = LLMConfigurationHistory.canonicalBaseURLKey(baseURL)
        return builtIn.first {
            LLMConfigurationHistory.canonicalBaseURLKey($0.baseURL) == key
        }
    }

    func supports(modelID: String) -> Bool {
        guard let supportedModelPrefixes else { return true }
        return supportedModelPrefixes.contains { modelID.hasPrefix($0) }
    }
}

enum LLMModelCatalogError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case noModels
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL 格式无效"
        case .invalidResponse:
            return "模型列表返回格式无法识别"
        case .noModels:
            return "厂商返回的模型列表为空"
        case let .httpStatus(statusCode, message):
            switch statusCode {
            case 401, 403:
                return "鉴权失败，请检查 API Key 与 Base URL"
            case 404:
                return "当前地址未提供兼容的模型列表接口"
            default:
                if let message, !message.isEmpty {
                    return "获取失败（HTTP \(statusCode)）：\(message)"
                }
                return "获取失败（HTTP \(statusCode)）"
            }
        }
    }
}

final class LLMModelCatalogService {
    static let shared = LLMModelCatalogService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let url = try modelListURL(for: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMModelCatalogError.httpStatus(
                httpResponse.statusCode,
                serverErrorMessage(from: data)
            )
        }

        let preset = LLMProviderPreset.matching(baseURL: baseURL)
        let models = try decodeModelIDs(from: data).filter {
            preset?.supports(modelID: $0) ?? true
        }
        guard !models.isEmpty else {
            throw LLMModelCatalogError.noModels
        }
        return models
    }

    func modelListURL(for baseURL: String) throws -> URL {
        let normalized = BridgeService.normalizedLLMBaseURL(baseURL)
        guard var components = URLComponents(string: normalized),
              components.scheme != nil,
              components.host != nil
        else {
            throw LLMModelCatalogError.invalidBaseURL
        }

        let currentPath = components.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        if currentPath.split(separator: "/").last != "models" {
            components.path = "/\(currentPath)/models"
        }

        guard let url = components.url else {
            throw LLMModelCatalogError.invalidBaseURL
        }
        return url
    }

    func decodeModelIDs(from data: Data) throws -> [String] {
        let decoder = JSONDecoder()
        let records: [ModelRecord]

        if let envelope = try? decoder.decode(ModelEnvelope.self, from: data) {
            records = envelope.data ?? envelope.models ?? []
        } else if let rootRecords = try? decoder.decode([ModelRecord].self, from: data) {
            records = rootRecords
        } else {
            throw LLMModelCatalogError.invalidResponse
        }

        var seen = Set<String>()
        return records
            .compactMap(\.identifier)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func serverErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        if let message = dictionary["message"] as? String {
            return message
        }
        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        return nil
    }
}

private struct ModelEnvelope: Decodable {
    let data: [ModelRecord]?
    let models: [ModelRecord]?
}

private struct ModelRecord: Decodable {
    let identifier: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            identifier = value
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier =
            try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .name)
    }
}
