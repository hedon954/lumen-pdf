import Foundation

@MainActor
final class LLMConfigurationModel: ObservableObject {
    @Published private(set) var fetchedModels: [String] = []
    @Published private(set) var fetchedBaseURLKey = ""
    @Published private(set) var recentBaseURLs: [String]
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelListMessage: String?
    @Published private(set) var modelListMessageIsError = false

    private let catalogService: LLMModelCatalogService
    private let history: LLMConfigurationHistory
    private var activeRequestID: UUID?

    init(
        catalogService: LLMModelCatalogService = .shared,
        history: LLMConfigurationHistory = .shared
    ) {
        self.catalogService = catalogService
        self.history = history
        recentBaseURLs = history.recentBaseURLs()
    }

    func remember(baseURL: String, model: String) {
        history.remember(baseURL: baseURL, model: model)
        recentBaseURLs = history.recentBaseURLs()
    }

    func recentModels(for baseURL: String) -> [String] {
        history.recentModels(for: baseURL)
    }

    func availableModels(for baseURL: String) -> [String] {
        let recent = history.recentModels(for: baseURL)
        let fetched =
            fetchedBaseURLKey == LLMConfigurationHistory.canonicalBaseURLKey(baseURL)
                ? fetchedModels
                : []

        var seen = Set<String>()
        return (recent + fetched).filter { seen.insert($0).inserted }
    }

    func refreshModels(baseURL: String, apiKey: String) async {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else {
            modelListMessage = "请先填写或选择 Base URL"
            modelListMessageIsError = true
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        isLoadingModels = true
        modelListMessageIsError = false

        let providerName =
            LLMProviderPreset.matching(baseURL: trimmedBaseURL)?.name ?? "当前厂商"
        modelListMessage = "正在从\(providerName)获取模型列表…"

        do {
            let models = try await catalogService.fetchModels(
                baseURL: trimmedBaseURL,
                apiKey: apiKey
            )
            guard activeRequestID == requestID else { return }

            fetchedModels = models
            fetchedBaseURLKey = LLMConfigurationHistory.canonicalBaseURLKey(trimmedBaseURL)
            modelListMessage = "已获取 \(models.count) 个可用模型"
            modelListMessageIsError = false
        } catch {
            guard activeRequestID == requestID else { return }

            fetchedModels = []
            fetchedBaseURLKey = LLMConfigurationHistory.canonicalBaseURLKey(trimmedBaseURL)
            modelListMessage =
                "\(error.localizedDescription)；仍可手动填写模型名称"
            modelListMessageIsError = true
        }

        if activeRequestID == requestID {
            isLoadingModels = false
        }
    }

    func shouldAutomaticallyRefresh(baseURL: String, apiKey: String) -> Bool {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return LLMProviderPreset.matching(baseURL: baseURL)?.id == "openrouter"
    }
}
