import Foundation

/// Maps UniFFI `LumenError` to user-visible Chinese messages for the translation bubble.
enum TranslationErrorFormatter {
    static func userMessage(from error: Error) -> String {
        if let re = error as? LumenError {
            switch re {
            case .ConfigNotInitialized:
                return "LLM 未就绪：请先在「设置」中填写 API Base URL、API Key 与模型，保存后再试。"
            case .DatabaseError(let message):
                return "数据库错误：\(message)"
            case .LlmApiError(let message):
                return "LLM 接口调用失败：\(cleanLLMMessage(message))"
            case .FallbackApiError(let message):
                return "兜底翻译接口（MyMemory）失败：\(message)"
            case .SerializationError(let message):
                return "译文解析失败（JSON 格式）：\(message)"
            case .NotFound(let message):
                return "未找到：\(message)"
            }
        }
        return "翻译失败：\(error.localizedDescription)"
    }

    private static func cleanLLMMessage(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("invalid_api_key")
            || lowercased.contains("invalid api-key")
            || lowercased.contains("401 unauthorized") {
            return "API Key 无效或已失效，请在「设置」中更新后重试。"
        }

        if lowercased.contains("unauthorized") || lowercased.contains("401") {
            return "认证失败，请检查 API Key、Base URL 和模型配置。"
        }

        if let serverMessage = serverErrorMessage(from: message), !serverMessage.isEmpty {
            return serverMessage
        }

        return message
    }

    private static func serverErrorMessage(from message: String) -> String? {
        guard let jsonStart = message.firstIndex(of: "{"),
              let data = String(message[jsonStart...]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any]
        else { return nil }

        if let code = error["code"] as? String, code == "invalid_api_key" {
            return "API Key 无效或已失效，请在「设置」中更新后重试。"
        }

        return error["message"] as? String
    }
}
