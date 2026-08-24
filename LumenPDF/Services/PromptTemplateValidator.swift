import Foundation

struct PromptTemplateVariable: Identifiable, Equatable {
    let name: String
    let description: String

    var id: String { name }
    var token: String { "{\(name)}" }
}

enum PromptTemplateKind: String, CaseIterable, Identifiable {
    case word
    case sentence
    case explanation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word: return "单词翻译"
        case .sentence: return "整句翻译"
        case .explanation: return "选区解释"
        }
    }

    var systemImage: String {
        switch self {
        case .word: return "textformat.abc"
        case .sentence: return "text.alignleft"
        case .explanation: return "sparkles"
        }
    }

    var variables: [PromptTemplateVariable] {
        switch self {
        case .word:
            return [
                PromptTemplateVariable(name: "lang", description: "当前设置的目标语言，例如“简体中文”"),
                PromptTemplateVariable(name: "word", description: "PDF 中选中的单词原文，可能包含 OCR 或断词噪声"),
                PromptTemplateVariable(name: "sentence", description: "选中单词所在的上下文句子")
            ]
        case .sentence:
            return [
                PromptTemplateVariable(name: "lang", description: "当前设置的目标语言，例如“简体中文”"),
                PromptTemplateVariable(name: "sentence", description: "需要翻译的完整选中句子")
            ]
        case .explanation:
            return [
                PromptTemplateVariable(name: "lang", description: "当前设置的目标语言，例如“简体中文”"),
                PromptTemplateVariable(name: "selection", description: "PDF 中当前选中的原文"),
                PromptTemplateVariable(name: "context", description: "选区前后的正文上下文，用于补充语境"),
                PromptTemplateVariable(name: "focus", description: "用户在 AI 解释输入框中的问题；直接解释时为空")
            ]
        }
    }

    var allowedVariables: Set<String> { Set(variables.map(\.name)) }

    var requiredVariables: Set<String> { allowedVariables }
}

struct PromptTemplateValidation: Equatable {
    let errors: [String]
    let variables: [String]

    var isValid: Bool { errors.isEmpty }
}

enum PromptTemplateValidator {
    private static let variablePattern = try! NSRegularExpression(
        pattern: #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#
    )

    static func validateUserPrompt(
        _ template: String,
        kind: PromptTemplateKind
    ) -> PromptTemplateValidation {
        var errors: [String] = []
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors.append("User Prompt 不能为空")
        }

        let variables = extractedVariables(from: template)
        let variableSet = Set(variables)
        let unknown = variableSet.subtracting(kind.allowedVariables).sorted()
        if !unknown.isEmpty {
            errors.append("存在未知变量：\(unknown.map { "{\($0)}" }.joined(separator: "、"))")
        }
        let missing = kind.requiredVariables.subtracting(variableSet).sorted()
        if !missing.isEmpty {
            errors.append("缺少必需变量：\(missing.map { "{\($0)}" }.joined(separator: "、"))")
        }

        return PromptTemplateValidation(errors: errors, variables: variables)
    }

    static func validateSystemPrompt(_ template: String) -> PromptTemplateValidation {
        var errors: [String] = []
        if template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("System Prompt 不能为空")
        }
        let variables = extractedVariables(from: template)
        if !variables.isEmpty {
            errors.append(
                "System Prompt 不支持动态变量：\(variables.map { "{\($0)}" }.joined(separator: "、"))"
            )
        }
        return PromptTemplateValidation(errors: errors, variables: variables)
    }

    static func validatePair(
        userPrompt: String,
        systemPrompt: String,
        kind: PromptTemplateKind
    ) -> PromptTemplateValidation {
        let user = validateUserPrompt(userPrompt, kind: kind)
        let system = validateSystemPrompt(systemPrompt)
        return PromptTemplateValidation(
            errors: user.errors + system.errors,
            variables: user.variables
        )
    }

    private static func extractedVariables(from template: String) -> [String] {
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        var seen = Set<String>()
        return variablePattern.matches(in: template, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: template) else { return nil }
            let variable = String(template[captureRange])
            return seen.insert(variable).inserted ? variable : nil
        }
    }
}
