import Foundation

/// Structured, UI-independent view of a translation failure string.
///
/// Backend errors currently arrive as one concatenated diagnostic dump. The
/// overlay should show a short cause first and keep protocol details folded.
struct TranslationFailurePresentation: Equatable {
    enum Channel: Equatable {
        case llm
        case fallback
        case configuration
        case parsing
        case database
        case generic
    }

    enum Cause: Equatable {
        case quota
        case authentication
        case configuration
        case emptyOutput
        case parsing
        case network
        case unknown
    }

    struct Fact: Equatable, Identifiable {
        let label: String
        let value: String

        var id: String { "\(label)|\(value)" }
    }

    let rawMessage: String
    let channel: Channel
    let cause: Cause
    let headline: String
    let summary: String
    let hint: String
    let highlights: [Fact]
    let diagnostics: [Fact]
    let rawPreview: String?

    var hasTechnicalDetails: Bool {
        !diagnostics.isEmpty || !(rawPreview?.isEmpty ?? true)
    }

    var channelLabel: String {
        switch channel {
        case .llm: return "LLM 接口"
        case .fallback: return "兜底翻译"
        case .configuration: return "LLM 配置"
        case .parsing: return "译文解析"
        case .database: return "数据库"
        case .generic: return "翻译"
        }
    }

    var systemImage: String {
        switch cause {
        case .quota: return "chart.bar.xaxis"
        case .authentication: return "key.fill"
        case .configuration: return "gear"
        case .emptyOutput: return "text.badge.xmark"
        case .parsing: return "curlybraces"
        case .network: return "wifi.slash"
        case .unknown: return "exclamationmark.triangle.fill"
        }
    }

    static func parse(_ message: String, fallbackHeadline: String) -> TranslationFailurePresentation {
        let raw = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let (channel, remainder) = stripPrefix(from: raw)
        let fields = DiagnosticFields(from: remainder)
        let cause = inferCause(from: remainder, channel: channel, fields: fields)
        let headline = headlineText(for: cause, fallback: fallbackHeadline)
        let summary = summaryText(from: remainder, fields: fields, cause: cause, fallbackHeadline: fallbackHeadline)
        let hint = hintText(for: cause, summary: summary)
        return TranslationFailurePresentation(
            rawMessage: raw.isEmpty ? fallbackHeadline : raw,
            channel: channel,
            cause: cause,
            headline: headline,
            summary: summary,
            hint: hint,
            highlights: highlightFacts(fields: fields),
            diagnostics: diagnosticFacts(fields: fields),
            rawPreview: fields.prettyPreview
        )
    }
}

private struct DiagnosticFields {
    var requestURL: String?
    var model: String?
    var businessCode: String?
    var errorType: String?
    var errorCode: String?
    var streamSummary: String?
    var tokenSummary: String?
    let finishReason: String?
    let gatewayError: String?
    let ignoredPreview: String?
    let reasoningPreview: String?
    let rawPreview: String?
    let prettyPreview: String?
    let lead: String

    init(from text: String) {
        requestURL = Self.value(after: "请求地址：", in: text)
        model = Self.cleanModel(Self.value(after: "模型：", in: text))
        finishReason = Self.value(after: "finish_reason：", in: text)
        gatewayError = Self.value(after: "网关错误：", in: text)
        ignoredPreview = Self.value(after: "未识别帧预览：", in: text)
        reasoningPreview = Self.reasoning(from: text)
        let preview = Self.value(after: "原始响应预览：", in: text)
            ?? (text.contains("原始响应完全为空") ? nil : Self.firstJSONObject(in: text))
        rawPreview = preview
        prettyPreview = Self.prettyJSON(preview)

        if let stream = Self.firstMatch(
            #"收到 (\d+) 字节，成功解析 (\d+) 个流式帧，忽略 (\d+) 个无法识别的帧"#,
            in: text
        ) {
            let ignored = stream[2] == "0" ? "" : " · 忽略 \(stream[2]) 帧"
            streamSummary = "\(stream[0]) 字节 · \(stream[1]) 帧\(ignored)"
        }

        if text.contains("Token 用量为 0") {
            tokenSummary = "0（模型未开始推理）"
        } else if let tokens = Self.firstMatch(
            #"Token：输入 (\d+)，输出 (\d+)，合计 (\d+)"#,
            in: text
        ) {
            tokenSummary = "输入 \(tokens[0]) · 输出 \(tokens[1]) · 合计 \(tokens[2])"
        }

        if let json = preview, let parsed = Self.jsonObject(json) {
            let error = parsed["error"] as? [String: Any]
            let rootType = stringValue(parsed["type"])
            errorType = stringValue(error?["type"])
                ?? rootType.flatMap { $0 == "error" ? nil : $0 }
            errorCode = stringValue(error?["code"])
            if businessCode == nil {
                businessCode = Self.bracketCode(in: stringValue(error?["message"]) ?? "")
            }
        }

        lead = Self.leadText(from: text)
        if businessCode == nil {
            businessCode = Self.bracketCode(in: lead)
                ?? Self.bracketCode(in: gatewayError ?? "")
                ?? Self.bracketCode(in: preview ?? "")
        }
    }

    private static func leadText(from text: String) -> String {
        let markers = [
            "模型没有返回任何可用正文",
            "模型没有返回任何内容",
            "请求地址：",
            "收到 ",
            "Token 用量为 0",
            "Token：输入",
            "finish_reason：",
            "网关错误：",
            "模型只返回了思考过程",
            "未识别帧预览：",
            "原始响应预览：",
            "原始响应完全为空",
        ]
        let end = earliestIndex(of: markers, in: text) ?? text.endIndex
        return sanitizeUserText(String(text[..<end]))
    }

    private static func reasoning(from text: String) -> String? {
        guard let range = text.range(of: "思考预览：") else { return nil }
        return value(after: "思考预览：", in: String(text[range.lowerBound...]))
    }

    private static func value(after label: String, in text: String) -> String? {
        guard let start = text.range(of: label)?.upperBound else { return nil }
        let markers = [
            "请求地址：",
            "模型：",
            "收到 ",
            "Token 用量为 0",
            "Token：输入",
            "finish_reason：",
            "网关错误：",
            "模型只返回了思考过程",
            "未识别帧预览：",
            "原始响应预览：",
            "原始响应完全为空",
            "思考预览：",
        ]
        let remainder = String(text[start...])
        let end = earliestIndex(of: markers.filter { $0 != label }, in: remainder) ?? remainder.endIndex
        let value = sanitizeUserText(String(remainder[..<end]))
        return value.isEmpty ? nil : value
    }

    private static func cleanModel(_ value: String?) -> String? {
        guard var model = value, !model.isEmpty else { return nil }
        if model == "未配置" { return model }
        if let cut = model.range(of: " ") {
            model = String(model[..<cut.lowerBound])
        }
        return model.isEmpty ? nil : model
    }

    private static func bracketCode(in text: String) -> String? {
        guard let match = firstMatch(#"\[([A-Za-z][A-Za-z0-9_]{1,47})\]"#, in: text),
              let code = match.first
        else { return nil }
        return code
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text[start...].lastIndex(of: "}")
        else { return nil }
        return String(text[start...end])
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        let candidates = [text, text.trimmingCharacters(in: CharacterSet(charactersIn: "…"))]
        for candidate in candidates {
            guard let start = candidate.firstIndex(of: "{") else { continue }
            let slice = String(candidate[start...])
            if let data = slice.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    private static func prettyJSON(_ text: String?) -> String? {
        guard let text, let object = jsonObject(text) else { return text }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return text }
        return String(data: data, encoding: .utf8) ?? text
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { continue }
            captures.append(String(text[range]))
        }
        return captures.isEmpty ? nil : captures
    }

    private static func earliestIndex(of markers: [String], in text: String) -> String.Index? {
        markers.compactMap { text.range(of: $0)?.lowerBound }.min()
    }
}

private func stripPrefix(from text: String) -> (TranslationFailurePresentation.Channel, String) {
    let prefixes: [(String, TranslationFailurePresentation.Channel)] = [
        ("LLM 接口调用失败：", .llm),
        ("LLM 接口失败：", .llm),
        ("LLM 调用失败：", .llm),
        ("LLM 调用未成功：", .llm),
        ("兜底翻译接口（MyMemory）失败：", .fallback),
        ("兜底翻译接口失败：", .fallback),
        ("兜底翻译部分失败：", .fallback),
        ("兜底翻译失败：", .fallback),
        ("译文解析失败（JSON 格式）：", .parsing),
        ("译文解析失败：", .parsing),
        ("LLM 未就绪：", .configuration),
        ("数据库错误：", .database),
        ("未找到：", .generic),
        ("翻译失败：", .generic),
    ]
    for (prefix, channel) in prefixes where text.hasPrefix(prefix) {
        return (channel, String(text.dropFirst(prefix.count)))
    }
    if text.contains("MyMemory") || text.contains("兜底") {
        return (.fallback, text)
    }
    if text.contains("LLM") || text.contains("模型没有返回") || text.contains("请求地址：") {
        return (.llm, text)
    }
    return (.generic, text)
}

private func inferCause(
    from text: String,
    channel: TranslationFailurePresentation.Channel,
    fields: DiagnosticFields
) -> TranslationFailurePresentation.Cause {
    let haystack = (text + " " + (fields.gatewayError ?? "") + " " + (fields.rawPreview ?? "")).lowercased()
    if channel == .configuration || haystack.contains("llm 未就绪") {
        return .configuration
    }
    if channel == .parsing || (haystack.contains("json") && haystack.contains("解析失败")) {
        return .parsing
    }
    if haystack.contains("额度")
        || haystack.contains("quota")
        || haystack.contains("rate limit")
        || haystack.contains("429")
        || haystack.contains("insufficient_quota") {
        return .quota
    }
    if haystack.contains("invalid_api_key")
        || haystack.contains("api key")
        || haystack.contains("api-key")
        || haystack.contains("认证失败")
        || haystack.contains("unauthorized")
        || haystack.contains("401") {
        return .authentication
    }
    if haystack.contains("网络")
        || haystack.contains("network")
        || haystack.contains("timed out")
        || haystack.contains("timeout")
        || haystack.contains("connection") {
        return .network
    }
    if haystack.contains("模型没有返回")
        || haystack.contains("空响应")
        || haystack.contains("没有返回任何可用正文")
        || haystack.contains("没有返回任何内容") {
        return .emptyOutput
    }
    return .unknown
}

private func headlineText(
    for cause: TranslationFailurePresentation.Cause,
    fallback: String
) -> String {
    switch cause {
    case .quota: return "额度已用完"
    case .authentication: return "认证失败"
    case .configuration: return "LLM 未就绪"
    case .emptyOutput: return "模型没有返回内容"
    case .parsing: return "译文解析失败"
    case .network: return "网络请求失败"
    case .unknown: return fallback
    }
}

private func summaryText(
    from text: String,
    fields: DiagnosticFields,
    cause: TranslationFailurePresentation.Cause,
    fallbackHeadline: String
) -> String {
    let candidates = [
        fields.lead,
        fields.gatewayError.map(sanitizeUserText) ?? "",
        jsonMessage(from: fields.rawPreview),
    ]
    .map { stripBracketCode($0) }
    .map(sanitizeUserText)
    .filter { !$0.isEmpty && !isDiagnosticFiller($0) }

    if let first = candidates.first {
        return first
    }

    switch cause {
    case .quota:
        return "当前接口额度已用完，暂时无法完成翻译。"
    case .authentication:
        return "API Key 无效或已失效，请在「设置」中更新后重试。"
    case .configuration:
        return "请先在「设置」中填写 API Base URL、API Key 与模型并保存。"
    case .emptyOutput:
        return "模型没有返回任何可用正文，请求可能在到达模型前被拒绝。"
    case .parsing:
        return "模型返回了无法解析的内容。"
    case .network:
        return "网络请求失败，请检查连接后重试。"
    case .unknown:
        let trimmed = sanitizeUserText(text)
        if trimmed.isEmpty {
            return fallbackHeadline == "翻译未完成"
                ? "请检查网络与 LLM 设置后重试。"
                : fallbackHeadline
        }
        return trimmed
    }
}

private func hintText(for cause: TranslationFailurePresentation.Cause, summary: String) -> String {
    let hint: String
    switch cause {
    case .quota:
        hint = "请更换模型、检查平台配额，或到「设置」切换接口后再试。"
    case .authentication:
        hint = "请打开「设置」更新 API Key、Base URL 和模型后再试。"
    case .configuration:
        hint = "保存 LLM 配置后，点击右上角刷新即可重新翻译。"
    case .emptyOutput:
        hint = "可打开「设置 → 调用日志」查看原始响应，或更换模型后重试。"
    case .parsing:
        hint = "可打开「设置 → 调用日志」查看原始响应后再判断。"
    case .network:
        hint = "请检查网络连接后，点击重试。"
    case .unknown:
        hint = "请检查网络与 LLM 设置后，点击右上角刷新重试。"
    }
    if summary.contains(hint) || hint.contains(summary) {
        return ""
    }
    if summary.contains("请") && (cause == .authentication || cause == .configuration) {
        return ""
    }
    return hint
}

private func highlightFacts(
    fields: DiagnosticFields
) -> [TranslationFailurePresentation.Fact] {
    var facts: [TranslationFailurePresentation.Fact] = []
    func append(_ label: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        facts.append(.init(label: label, value: value))
    }
    append("模型", fields.model)
    append("业务码", fields.businessCode)
    append("错误码", fields.errorCode)
    append("类型", fields.errorType)
    return facts
}

private func diagnosticFacts(fields: DiagnosticFields) -> [TranslationFailurePresentation.Fact] {
    var facts: [TranslationFailurePresentation.Fact] = []
    func append(_ label: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        facts.append(.init(label: label, value: value))
    }
    append("请求地址", fields.requestURL)
    append("流式解析", fields.streamSummary)
    append("Token", fields.tokenSummary)
    append("finish_reason", fields.finishReason)
    if let gateway = fields.gatewayError,
       sanitizeUserText(gateway) != sanitizeUserText(fields.lead) {
        append("网关错误", gateway)
    }
    append("思考预览", fields.reasoningPreview)
    append("未识别帧", fields.ignoredPreview)
    return facts
}

private func jsonMessage(from preview: String?) -> String {
    guard let preview,
          let data = preview.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = root["error"] as? [String: Any],
          let message = error["message"] as? String
    else { return "" }
    return message
}

private func stripBracketCode(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"\s*\[[A-Za-z][A-Za-z0-9_]{1,47}\]"#) else {
        return text
    }
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
}

private func isDiagnosticFiller(_ text: String) -> Bool {
    text.contains("请求地址：")
        || text.contains("原始响应")
        || text.contains("成功解析")
        || text.contains("Token 用量为 0")
}

private func sanitizeUserText(_ text: String) -> String {
    let collapsed = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "。；;，, "))
}

private func stringValue(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}
