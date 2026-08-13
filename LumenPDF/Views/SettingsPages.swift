import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case llm
    case translation
    case prompts
    case logs
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llm: return "LLM"
        case .translation: return "翻译"
        case .prompts: return "提示词"
        case .logs: return "调用日志"
        case .usage: return "Token 与费用"
        }
    }

    var systemImage: String {
        switch self {
        case .llm: return "cpu"
        case .translation: return "character.book.closed"
        case .prompts: return "text.badge.star"
        case .logs: return "list.bullet.rectangle"
        case .usage: return "chart.bar.xaxis"
        }
    }
}

struct LLMSettingsPage: View {
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var model: String
    @ObservedObject var configuration: LLMConfigurationModel
    let onSubmit: () -> Void

    var body: some View {
        Form {
            LLMConfigurationSection(
                baseURL: $baseURL,
                apiKey: $apiKey,
                model: $model,
                configuration: configuration,
                onSubmit: onSubmit
            )
        }
        .formStyle(.grouped)
        .navigationTitle("LLM 配置")
    }
}

struct TranslationSettingsPage: View {
    @Binding var targetLanguage: String

    var body: some View {
        Form {
            Section("翻译语言") {
                Picker("目标语言", selection: $targetLanguage) {
                    Text("简体中文").tag("简体中文")
                    Text("繁體中文").tag("繁體中文")
                    Text("English").tag("English")
                    Text("日本語").tag("日本語")
                    Text("한국어").tag("한국어")
                }
            }

            Section {
                Text("内置提示词按中文或英文模板切换；繁体中文复用中文模板，其他目标语言复用英文模板，并通过 {lang} 生成目标语言内容。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("翻译设置")
    }
}

struct PromptSettingsPage: View {
    @Binding var selectedKind: PromptTemplateKind
    @Binding var wordPrompt: String
    @Binding var sentencePrompt: String
    @Binding var explanationPrompt: String
    @Binding var wordSystemPrompt: String
    @Binding var sentenceSystemPrompt: String
    @Binding var explanationSystemPrompt: String

    let defaults: PromptTemplateDefaults.LanguageDefaults
    let pendingUpdateTitles: [String]
    let onKeepCustomTemplates: () -> Void
    let onAcceptLatestTemplates: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("提示词类型", selection: $selectedKind) {
                ForEach(PromptTemplateKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !pendingUpdateTitles.isEmpty {
                        promptUpdateCard
                    }

                    switch selectedKind {
                    case .word:
                        PromptTemplateEditor(
                            kind: .word,
                            userPrompt: $wordPrompt,
                            systemPrompt: $wordSystemPrompt,
                            defaultUserPrompt: defaults.word,
                            defaultSystemPrompt: defaults.wordSystem
                        )
                    case .sentence:
                        PromptTemplateEditor(
                            kind: .sentence,
                            userPrompt: $sentencePrompt,
                            systemPrompt: $sentenceSystemPrompt,
                            defaultUserPrompt: defaults.sentence,
                            defaultSystemPrompt: defaults.sentenceSystem
                        )
                    case .explanation:
                        PromptTemplateEditor(
                            kind: .explanation,
                            userPrompt: $explanationPrompt,
                            systemPrompt: $explanationSystemPrompt,
                            defaultUserPrompt: defaults.explanation,
                            defaultSystemPrompt: defaults.explanationSystem
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("提示词模板")
    }

    private var promptUpdateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("系统提示词已有更新", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text("检测到以下模板包含自定义内容，因此没有自动覆盖：\(pendingUpdateTitles.joined(separator: "、"))")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("保留自定义", action: onKeepCustomTemplates)
                Button("使用新版", action: onAcceptLatestTemplates)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.7)
        }
    }
}

private struct PromptTemplateEditor: View {
    let kind: PromptTemplateKind
    @Binding var userPrompt: String
    @Binding var systemPrompt: String
    let defaultUserPrompt: String
    let defaultSystemPrompt: String

    @State private var validationFeedback: PromptTemplateValidation?

    private var liveValidation: PromptTemplateValidation {
        let user = PromptTemplateValidator.validateUserPrompt(userPrompt, kind: kind)
        let system = PromptTemplateValidator.validateSystemPrompt(systemPrompt)
        return PromptTemplateValidation(
            errors: user.errors + system.errors,
            variables: user.variables
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Button {
                    validationFeedback = liveValidation
                } label: {
                    Label("验证提示词", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
            }

            variableGuide

            editor(
                title: "User Prompt",
                text: $userPrompt,
                defaultValue: defaultUserPrompt,
                minimumHeight: 250
            )
            editor(
                title: "System Prompt",
                text: $systemPrompt,
                defaultValue: defaultSystemPrompt,
                minimumHeight: 110
            )

            validationCard(validationFeedback ?? liveValidation)
        }
        .onChange(of: userPrompt) { _, _ in validationFeedback = nil }
        .onChange(of: systemPrompt) { _, _ in validationFeedback = nil }
    }

    private var variableGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("可用变量", systemImage: "curlybraces")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(kind.variables) { variable in
                    GridRow {
                        Text(variable.token)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.tint)
                        Text(variable.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private func editor(
        title: String,
        text: Binding<String>,
        defaultValue: String,
        minimumHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("恢复系统默认") { text.wrappedValue = defaultValue }
            }
            TextEditor(text: text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minimumHeight)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 0.7)
                }
        }
    }

    private func validationCard(_ result: PromptTemplateValidation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                result.isValid ? "验证通过" : "需要修正",
                systemImage: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(result.isValid ? .green : .orange)

            if result.isValid {
                Text("动态变量完整且名称有效，可以保存并用于下一次调用。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.errors, id: \.self) { error in
                    Text("• \(error)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LLMCallLogSettingsPage: View {
    @ObservedObject private var store: LLMCallLogStore
    @State private var selectedID: UUID?
    @State private var isConfirmingClear = false

    @MainActor
    init() {
        self.store = .shared
    }

    @MainActor
    init(store: LLMCallLogStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LLM 调用日志")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("清空日志", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(store.entries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.entries) { entry in
                        LogRow(entry: entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 230)

                Divider()

                Group {
                    if let entry = selectedEntry {
                        LLMCallLogDetail(entry: entry)
                    } else {
                        ContentUnavailableView(
                            store.entries.isEmpty ? "暂无调用日志" : "选择一条调用日志",
                            systemImage: "list.bullet.rectangle",
                            description: Text(
                                store.entries.isEmpty
                                    ? "完成一次 LLM 调用后，可在这里审计输入、输出、失败原因和 Token。"
                                    : "查看输入、响应、失败原因、耗时与 Token 用量"
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "确定清空全部 LLM 调用日志？",
            isPresented: $isConfirmingClear
        ) {
            Button("清空全部日志", role: .destructive) {
                store.clear()
                selectedID = nil
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.entries.first?.id
            }
        }
    }

    private var selectedEntry: LLMCallLogEntry? {
        store.entries.first { $0.id == selectedID }
    }
}

private struct LogRow: View {
    let entry: LLMCallLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.kind.title)
                    .font(.body.weight(.medium))
                Text(entry.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusIcon: String {
        switch entry.status {
        case .running: return "clock"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .running: return .orange
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

private struct LLMCallLogDetail: View {
    let entry: LLMCallLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("类型", value: entry.kind.title)
                LabeledContent("模型", value: entry.model)
                LabeledContent("来源", value: entry.source.isEmpty ? "—" : entry.source)
                if let duration = entry.duration {
                    LabeledContent("耗时", value: String(format: "%.2f 秒", duration))
                }
                LabeledContent(
                    "Token",
                    value: "输入 \(entry.promptTokens) · 输出 \(entry.completionTokens) · 合计 \(entry.totalTokens)"
                )

                if !entry.errorMessage.isEmpty {
                    logTextSection("错误 / 警告", text: entry.errorMessage, tint: .red)
                }
                logTextSection("输入", text: entry.input, tint: .secondary)
                logTextSection("输出", text: entry.output.isEmpty ? "暂无输出" : entry.output, tint: .secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func logTextSection(_ title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LLMUsageSettingsPage: View {
    @Binding var currentModel: String
    @ObservedObject private var logStore: LLMCallLogStore
    @ObservedObject private var pricingStore: LLMPricingStore

    @State private var inputPrice = ""
    @State private var outputPrice = ""
    @State private var savedPricing = false

    @MainActor
    init(currentModel: Binding<String>) {
        _currentModel = currentModel
        self.logStore = .shared
        self.pricingStore = .shared
    }

    @MainActor
    init(
        currentModel: Binding<String>,
        logStore: LLMCallLogStore,
        pricingStore: LLMPricingStore
    ) {
        _currentModel = currentModel
        self.logStore = logStore
        self.pricingStore = pricingStore
    }

    private var summary: LLMUsageSummary {
        LLMUsageSummary(entries: logStore.entries, pricingStore: pricingStore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    metricCard("调用次数", value: "\(summary.calls)", icon: "arrow.trianglehead.2.clockwise")
                    metricCard("输入 Token", value: summary.promptTokens.formatted(), icon: "arrow.up.doc")
                    metricCard("输出 Token", value: summary.completionTokens.formatted(), icon: "arrow.down.doc")
                    metricCard(
                        "估算费用",
                        value: summary.estimatedCostUSD.formatted(.currency(code: "USD")),
                        icon: "dollarsign.circle"
                    )
                }
                Text("Token 来自模型兼容接口返回的 usage 字段；服务商未返回 usage 时，该次调用会记录为 0。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GroupBox("当前模型单价") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("模型", value: currentModel.isEmpty ? "未配置模型" : currentModel)
                        LabeledContent("输入价格（USD / 1M Token）") {
                            TextField("0", text: $inputPrice)
                                .frame(width: 140)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("输出价格（USD / 1M Token）") {
                            TextField("0", text: $outputPrice)
                                .frame(width: 140)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("费用为本地估算；实际账单以模型服务商为准。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if savedPricing {
                                Label("已保存", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            Button("保存单价", action: savePricing)
                                .buttonStyle(.borderedProminent)
                                .disabled(currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("按模型统计").font(.title3.weight(.semibold))
                    if groupedEntries.isEmpty {
                        Text("完成一次 LLM 调用后，这里会显示按模型汇总的 Token 与费用。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupedEntries, id: \.model) { group in
                            let groupSummary = LLMUsageSummary(
                                entries: group.entries,
                                pricingStore: pricingStore
                            )
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.model).font(.headline)
                                    Text("\(groupSummary.calls) 次调用")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(groupSummary.totalTokens.formatted()) Token")
                                    .monospacedDigit()
                                Text(groupSummary.estimatedCostUSD.formatted(.currency(code: "USD")))
                                    .monospacedDigit()
                                    .frame(width: 100, alignment: .trailing)
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Token 与费用")
        .task(id: currentModel) { loadPricing() }
    }

    private var groupedEntries: [(model: String, entries: [LLMCallLogEntry])] {
        Dictionary(grouping: logStore.entries, by: \.model)
            .map { (model: $0.key, entries: $0.value) }
            .sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
    }

    private func metricCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func loadPricing() {
        let pricing = pricingStore.pricing(for: currentModel)
        inputPrice = pricing.inputUSDPerMillionTokens.formatted()
        outputPrice = pricing.outputUSDPerMillionTokens.formatted()
        savedPricing = false
    }

    private func savePricing() {
        pricingStore.update(
            model: currentModel,
            input: Double(inputPrice.replacingOccurrences(of: ",", with: ".")) ?? 0,
            output: Double(outputPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
        )
        savedPricing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            savedPricing = false
        }
    }
}
