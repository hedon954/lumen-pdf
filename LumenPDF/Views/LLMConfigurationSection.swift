import SwiftUI

struct LLMConfigurationSection: View {
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var extraConfig: String

    @ObservedObject var configuration: LLMConfigurationModel
    let onSubmit: () -> Void

    @State private var isModelPickerPresented = false
    @State private var modelSearch = ""
    @State private var draftAPIKeysByBaseURL: [String: String] = [:]
    @State private var draftExtraConfigByBaseURL: [String: String] = [:]

    var body: some View {
        Section {
            Picker("服务商", selection: providerSelection) {
                Section("内置服务商") {
                    ForEach(LLMProviderPreset.builtIn) { provider in
                        Text(provider.name)
                            .tag(providerTag(provider))
                    }
                }

                if !recentCustomBaseURLs.isEmpty {
                    Section("最近使用") {
                        ForEach(recentCustomBaseURLs, id: \.self) { recentBaseURL in
                            Text(recentBaseURL)
                                .lineLimit(1)
                                .tag(recentTag(recentBaseURL))
                        }
                    }
                }

                if LLMProviderPreset.matching(baseURL: baseURL) == nil,
                   !recentCustomBaseURLs.contains(where: {
                       LLMConfigurationHistory.canonicalBaseURLKey($0)
                           == LLMConfigurationHistory.canonicalBaseURLKey(baseURL)
                   })
                {
                    Text("自定义")
                        .tag(customTag)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Base URL") {
                TextField("", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Base URL")
                    .onSubmit {
                        configuration.remember(baseURL: baseURL, model: model)
                        onSubmit()
                        refreshModels()
                    }
            }

            LabeledContent("API Key") {
                SecureField("", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("API Key")
                    .onSubmit {
                        onSubmit()
                        refreshModels()
                    }
            }

            if let provider = LLMProviderPreset.matching(baseURL: baseURL) {
                Link(destination: provider.apiKeyURL) {
                    Label(
                        "获取 \(provider.name) API Key",
                        systemImage: "key.fill"
                    )
                }
                .font(.caption)
                .accessibilityHint("在浏览器中打开官方 API Key 申请页面")
            }

            LabeledContent("模型") {
                HStack(spacing: 6) {
                    TextField("", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("模型")
                        .onSubmit {
                            configuration.remember(baseURL: baseURL, model: model)
                            onSubmit()
                        }

                    Button {
                        modelSearch = ""
                        isModelPickerPresented.toggle()
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .help("从模型列表中选择")
                    .popover(
                        isPresented: $isModelPickerPresented,
                        arrowEdge: .bottom
                    ) {
                        modelPicker
                    }

                    if configuration.isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 24)
                    } else {
                        Button {
                            refreshModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.bordered)
                        .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("从当前服务商刷新模型列表")
                    }
                }
            }

            if let message = configuration.modelListMessage {
                Label(
                    message,
                    systemImage: configuration.modelListMessageIsError
                        ? "exclamationmark.triangle"
                        : "info.circle"
                )
                .font(.caption)
                .foregroundStyle(
                    configuration.modelListMessageIsError
                        ? Color.orange
                        : Color.secondary
                )
            } else {
                Text("选择服务商后会填入常用 Base URL；模型列表来自当前厂商的兼容接口，也可以继续手动输入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = LLMProviderPreset.matching(baseURL: baseURL)?.compatibilityNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: model) { oldModel, newModel in
            refreshDefaultExtraIfUnmodified(previousModel: oldModel, newModel: newModel)
        }
    }

    private var providerSelection: Binding<String> {
        Binding(
            get: {
                if let provider = LLMProviderPreset.matching(baseURL: baseURL) {
                    return providerTag(provider)
                }
                if let recentBaseURL = recentCustomBaseURLs.first(where: {
                    LLMConfigurationHistory.canonicalBaseURLKey($0)
                        == LLMConfigurationHistory.canonicalBaseURLKey(baseURL)
                }) {
                    return recentTag(recentBaseURL)
                }
                return customTag
            },
            set: { tag in
                if tag.hasPrefix("provider:"),
                   let provider = LLMProviderPreset.builtIn.first(where: {
                       providerTag($0) == tag
                   })
                {
                    selectBaseURL(provider.baseURL)
                } else if tag.hasPrefix("recent:") {
                    let encodedBaseURL = String(tag.dropFirst("recent:".count))
                    if let decodedBaseURL = encodedBaseURL.removingPercentEncoding {
                        selectBaseURL(decodedBaseURL)
                    }
                }
            }
        )
    }

    private var recentCustomBaseURLs: [String] {
        configuration.recentBaseURLs.filter {
            LLMProviderPreset.matching(baseURL: $0) == nil
        }
    }

    private var availableModels: [String] {
        var values = configuration.availableModels(for: baseURL)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty, !values.contains(trimmedModel) {
            values.insert(trimmedModel, at: 0)
        }
        return values
    }

    private var filteredModels: [String] {
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableModels }
        return availableModels.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private var modelPicker: some View {
        VStack(spacing: 10) {
            TextField("搜索模型", text: $modelSearch)
                .textFieldStyle(.roundedBorder)

            if filteredModels.isEmpty {
                ContentUnavailableView(
                    "暂无可选模型",
                    systemImage: "cube.transparent",
                    description: Text(
                        configuration.isLoadingModels
                            ? "正在获取模型列表…"
                            : "点击刷新，或直接在设置页手动输入模型名称。"
                    )
                )
            } else {
                List(filteredModels, id: \.self) { candidate in
                    Button {
                        model = candidate
                        configuration.remember(baseURL: baseURL, model: candidate)
                        isModelPickerPresented = false
                    } label: {
                        HStack {
                            Text(candidate)
                                .textSelection(.enabled)
                            Spacer()
                            if candidate == model {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(availableModels.count) 个模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刷新") {
                    refreshModels()
                }
                .disabled(configuration.isLoadingModels)
            }
        }
        .padding(12)
        .frame(width: 420, height: 340)
    }

    private var customTag: String {
        "custom"
    }

    private func providerTag(_ provider: LLMProviderPreset) -> String {
        "provider:\(provider.id)"
    }

    private func recentTag(_ baseURL: String) -> String {
        "recent:\(baseURL.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? baseURL)"
    }

    private func selectBaseURL(_ newBaseURL: String) {
        let previousBaseURL = baseURL
        let previousModel = model
        if LLMEndpointIdentity.isSame(previousBaseURL, newBaseURL) {
            if previousBaseURL != newBaseURL {
                baseURL = newBaseURL
            }
            return
        }

        let previousBaseURLKey = LLMEndpointIdentity.key(previousBaseURL)
        let newBaseURLKey = LLMEndpointIdentity.key(newBaseURL)
        draftAPIKeysByBaseURL[previousBaseURLKey] = apiKey
        draftExtraConfigByBaseURL[previousBaseURLKey] = extraConfig
        let providerAPIKey = draftAPIKeysByBaseURL[newBaseURLKey]
            ?? KeychainService.loadLLMAPIKey(for: newBaseURL)
            ?? ""
        extraConfig = LLMExtraConfig.prettyPrinted(
            draftExtraConfigByBaseURL[newBaseURLKey]
                ?? LLMSettingsStore().loadExtraConfig(for: newBaseURL)
        )
        apiKey = providerAPIKey
        baseURL = newBaseURL
        model = configuration.recentModels(for: newBaseURL).first ?? previousModel
        if extraConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extraConfig = LLMThinkingExtraConfig.defaultJSON(baseURL: newBaseURL, model: model)
        }
        Task {
            await Task.yield()
            configuration.remember(
                baseURL: previousBaseURL,
                model: previousModel
            )
            await configuration.refreshModels(
                baseURL: newBaseURL,
                apiKey: providerAPIKey
            )
        }
    }

    private func refreshDefaultExtraIfUnmodified(previousModel: String, newModel: String) {
        guard previousModel != newModel else { return }
        let previousDefault = LLMThinkingExtraConfig.defaultJSON(baseURL: baseURL, model: previousModel)
        if extraConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || LLMExtraConfig.jsonEquals(extraConfig, previousDefault)
        {
            extraConfig = LLMThinkingExtraConfig.defaultJSON(baseURL: baseURL, model: newModel)
        }
    }

    private func refreshModels() {
        let baseURLForRequest = baseURL
        let apiKeyForRequest = apiKey
        Task {
            await Task.yield()
            await configuration.refreshModels(
                baseURL: baseURLForRequest,
                apiKey: apiKeyForRequest
            )
        }
    }
}
