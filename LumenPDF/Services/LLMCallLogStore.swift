import Foundation

enum LLMCallKind: String, Codable, CaseIterable, Identifiable {
    case wordTranslation
    case sentenceTranslation
    case selectionExplanation
    case imageCapabilityCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wordTranslation: return "单词翻译"
        case .sentenceTranslation: return "整句翻译"
        case .selectionExplanation: return "选区解释"
        case .imageCapabilityCheck: return "图片能力检测"
        }
    }

    /// Only reading actions initiated by the user belong in the audit trail and
    /// usage accounting. Keep legacy internal cases decodable so older log
    /// files can be migrated without failing the entire file.
    var isUserFacing: Bool {
        switch self {
        case .wordTranslation, .sentenceTranslation, .selectionExplanation:
            return true
        case .imageCapabilityCheck:
            return false
        }
    }
}

enum LLMCallStatus: String, Codable {
    case running
    case succeeded
    case failed
}

struct LLMCallLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var finishedAt: Date?
    let kind: LLMCallKind
    let model: String
    let baseURL: String
    let input: String
    var output: String
    var status: LLMCallStatus
    var source: String
    var errorMessage: String
    var promptTokens: UInt64
    var completionTokens: UInt64
    var totalTokens: UInt64

    var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

@MainActor
final class LLMCallLogStore: ObservableObject {
    static let shared = LLMCallLogStore()

    @Published private(set) var entries: [LLMCallLogEntry]

    private let fileURL: URL
    private let maximumEntryCount: Int

    init(fileURL: URL? = nil, maximumEntryCount: Int = 500) {
        self.maximumEntryCount = maximumEntryCount
        self.fileURL = fileURL ?? Self.defaultFileURL()
        entries = Self.load(from: self.fileURL)
            .filter { $0.kind.isUserFacing }
            .map { entry in
                guard entry.status == .running else { return entry }
                var interrupted = entry
                interrupted.status = .failed
                interrupted.finishedAt = entry.finishedAt ?? Date()
                interrupted.errorMessage = "应用在调用结束前退出，未收到完整响应。"
                return interrupted
            }
        persist()
    }

    @discardableResult
    func begin(
        kind: LLMCallKind,
        model: String,
        baseURL: String,
        input: String
    ) -> UUID {
        precondition(kind.isUserFacing, "Internal LLM operations must not enter user call logs")
        let id = UUID()
        entries.insert(
            LLMCallLogEntry(
                id: id,
                startedAt: Date(),
                finishedAt: nil,
                kind: kind,
                model: Self.displayModel(model),
                baseURL: baseURL,
                input: Self.bounded(input),
                output: "",
                status: .running,
                source: "",
                errorMessage: "",
                promptTokens: 0,
                completionTokens: 0,
                totalTokens: 0
            ),
            at: 0
        )
        trimAndPersist()
        return id
    }

    func finish(
        id: UUID,
        output: String,
        source: String,
        promptTokens: UInt64,
        completionTokens: UInt64,
        totalTokens: UInt64,
        warning: String = "",
        failed: Bool = false
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].finishedAt = Date()
        entries[index].output = Self.bounded(output)
        entries[index].source = source
        entries[index].promptTokens = promptTokens
        entries[index].completionTokens = completionTokens
        entries[index].totalTokens = totalTokens
        entries[index].errorMessage = Self.bounded(warning)
        entries[index].status = failed ? .failed : .succeeded
        persist()
    }

    func fail(id: UUID, error: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].finishedAt = Date()
        entries[index].status = .failed
        entries[index].errorMessage = Self.bounded(error)
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func trimAndPersist() {
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Logging must never make an LLM call fail. The in-memory audit
            // trail remains available for the current app session.
        }
    }

    private static func load(from url: URL) -> [LLMCallLogEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LLMCallLogEntry].self, from: data)
        else { return [] }
        return decoded.sorted { $0.startedAt > $1.startedAt }
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("LumenPDF", isDirectory: true)
            .appendingPathComponent("llm-call-log.json")
    }

    private static func displayModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未配置模型" : trimmed
    }

    private static func bounded(_ text: String, limit: Int = 12_000) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "\n…（日志已截断）"
    }
}

struct LLMModelPricing: Codable, Equatable {
    var inputUSDPerMillionTokens: Double
    var outputUSDPerMillionTokens: Double

    static let zero = LLMModelPricing(
        inputUSDPerMillionTokens: 0,
        outputUSDPerMillionTokens: 0
    )
}

@MainActor
final class LLMPricingStore: ObservableObject {
    static let shared = LLMPricingStore()

    @Published private(set) var pricesByModel: [String: LLMModelPricing]

    private let defaults: UserDefaults
    private let storageKey = "llm_model_pricing_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: LLMModelPricing].self, from: data)
        {
            pricesByModel = decoded
        } else {
            pricesByModel = [:]
        }
    }

    func pricing(for model: String) -> LLMModelPricing {
        pricesByModel[normalized(model)] ?? .zero
    }

    func update(model: String, input: Double, output: Double) {
        let key = normalized(model)
        guard !key.isEmpty else { return }
        pricesByModel[key] = LLMModelPricing(
            inputUSDPerMillionTokens: max(0, input),
            outputUSDPerMillionTokens: max(0, output)
        )
        if let data = try? JSONEncoder().encode(pricesByModel) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func estimatedCost(for entry: LLMCallLogEntry) -> Double {
        let pricing = pricing(for: entry.model)
        return Double(entry.promptTokens) / 1_000_000 * pricing.inputUSDPerMillionTokens
            + Double(entry.completionTokens) / 1_000_000 * pricing.outputUSDPerMillionTokens
    }

    private func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct LLMUsageSummary {
    let calls: Int
    let promptTokens: UInt64
    let completionTokens: UInt64
    let totalTokens: UInt64
    let estimatedCostUSD: Double

    @MainActor
    init(entries: [LLMCallLogEntry], pricingStore: LLMPricingStore) {
        calls = entries.count
        promptTokens = entries.reduce(0) { $0 + $1.promptTokens }
        completionTokens = entries.reduce(0) { $0 + $1.completionTokens }
        totalTokens = entries.reduce(0) { $0 + $1.totalTokens }
        estimatedCostUSD = entries.reduce(0) {
            $0 + pricingStore.estimatedCost(for: $1)
        }
    }
}

struct LLMUsageCalendar: Equatable {
    struct Day: Identifiable, Equatable {
        let date: Date
        let calls: Int
        let promptTokens: UInt64
        let completionTokens: UInt64
        let totalTokens: UInt64
        let isFuture: Bool

        var id: Date { date }
    }

    let days: [Day]
    let weekCount: Int

    var weeks: [[Day]] {
        stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
    }

    var maximumCallsPerDay: Int {
        days.map(\.calls).max() ?? 0
    }

    init(
        entries: [LLMCallLogEntry],
        endingAt referenceDate: Date = Date(),
        weekCount: Int = 26,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let calendar = calendar
        let count = max(1, weekCount)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDay)?.start
            ?? referenceDay
        let firstWeekStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(count - 1),
            to: currentWeekStart
        ) ?? currentWeekStart

        struct Totals {
            var calls = 0
            var promptTokens: UInt64 = 0
            var completionTokens: UInt64 = 0
            var totalTokens: UInt64 = 0
        }

        let totalsByDay = entries.reduce(into: [Date: Totals]()) { result, entry in
            let day = calendar.startOfDay(for: entry.startedAt)
            result[day, default: Totals()].calls += 1
            result[day, default: Totals()].promptTokens += entry.promptTokens
            result[day, default: Totals()].completionTokens += entry.completionTokens
            result[day, default: Totals()].totalTokens += entry.totalTokens
        }

        self.weekCount = count
        days = (0..<(count * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstWeekStart) else {
                return nil
            }
            let totals = totalsByDay[date] ?? Totals()
            return Day(
                date: date,
                calls: totals.calls,
                promptTokens: totals.promptTokens,
                completionTokens: totals.completionTokens,
                totalTokens: totals.totalTokens,
                isFuture: date > referenceDay
            )
        }
    }
}
