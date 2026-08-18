import XCTest
@testable import LumenPDF

@MainActor
final class LLMCallLogStoreTests: XCTestCase {
    func testEmptyModelIsRecordedAsUnconfigured() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = LLMCallLogStore(fileURL: fileURL)
        _ = store.begin(
            kind: .selectionExplanation,
            model: "  ",
            baseURL: "https://api.openai.com/v1",
            input: "selection"
        )

        XCTAssertEqual(store.entries.first?.model, "未配置模型")
    }

    func testFinishedCallPersistsUsageAndCanBeReloaded() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = LLMCallLogStore(fileURL: fileURL)
        let id = store.begin(
            kind: .selectionExplanation,
            model: "test-model",
            baseURL: "https://example.test/v1",
            input: "selection"
        )
        store.finish(
            id: id,
            output: "explanation",
            source: "llm",
            promptTokens: 12,
            completionTokens: 8,
            totalTokens: 20
        )

        let reloaded = LLMCallLogStore(fileURL: fileURL)
        let entry = try XCTUnwrap(reloaded.entries.first)
        XCTAssertEqual(entry.status, .succeeded)
        XCTAssertEqual(entry.promptTokens, 12)
        XCTAssertEqual(entry.completionTokens, 8)
        XCTAssertEqual(entry.totalTokens, 20)
    }

    func testRunningCallBecomesFailedAfterReload() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = LLMCallLogStore(fileURL: fileURL)
        _ = store.begin(
            kind: .wordTranslation,
            model: "test-model",
            baseURL: "https://example.test/v1",
            input: "word"
        )

        let reloaded = LLMCallLogStore(fileURL: fileURL)
        let entry = try XCTUnwrap(reloaded.entries.first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertTrue(entry.errorMessage.contains("调用结束前退出"))
    }

    func testLegacyCapabilityChecksAreRemovedFromUserCallLog() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let legacyProbe = logEntry(
            startedAt: Date(),
            kind: .imageCapabilityCheck,
            model: "test-model",
            promptTokens: 0,
            completionTokens: 0
        )
        let readingCall = logEntry(
            startedAt: Date().addingTimeInterval(-1),
            kind: .selectionExplanation,
            model: "test-model",
            promptTokens: 12,
            completionTokens: 8
        )
        try JSONEncoder().encode([legacyProbe, readingCall]).write(to: fileURL)

        let migrated = LLMCallLogStore(fileURL: fileURL)
        XCTAssertEqual(migrated.entries.map(\.kind), [.selectionExplanation])

        let persisted = try JSONDecoder().decode(
            [LLMCallLogEntry].self,
            from: Data(contentsOf: fileURL)
        )
        XCTAssertEqual(persisted.map(\.kind), [.selectionExplanation])
    }

    func testPricingProducesExpectedLocalEstimate() throws {
        let suiteName = "LLMCallLogStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pricing = LLMPricingStore(defaults: defaults)
        pricing.update(model: "Test-Model", input: 2, output: 6)

        let entry = LLMCallLogEntry(
            id: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            kind: .sentenceTranslation,
            model: "test-model",
            baseURL: "https://example.test/v1",
            input: "input",
            output: "output",
            status: .succeeded,
            source: "llm",
            errorMessage: "",
            promptTokens: 500_000,
            completionTokens: 250_000,
            totalTokens: 750_000
        )

        XCTAssertEqual(pricing.estimatedCost(for: entry), 2.5, accuracy: 0.000_001)
    }

    func testUsageCalendarAggregatesCallsAndTokensByLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        calendar.firstWeekday = 2
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))
        )
        let firstCall = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))
        )
        let secondCall = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 23))
        )

        let usage = LLMUsageCalendar(
            entries: [
                logEntry(startedAt: firstCall, model: "model-a", promptTokens: 12, completionTokens: 8),
                logEntry(startedAt: secondCall, model: "model-b", promptTokens: 20, completionTokens: 5)
            ],
            endingAt: reference,
            weekCount: 2,
            calendar: calendar
        )

        let august10 = try XCTUnwrap(usage.days.first {
            calendar.component(.day, from: $0.date) == 10
        })
        XCTAssertEqual(usage.days.count, 14)
        XCTAssertEqual(usage.weeks.count, 2)
        XCTAssertEqual(august10.calls, 2)
        XCTAssertEqual(august10.promptTokens, 32)
        XCTAssertEqual(august10.completionTokens, 13)
        XCTAssertEqual(august10.totalTokens, 45)
        XCTAssertEqual(usage.maximumCallsPerDay, 2)
    }

    func testUsageCalendarMarksOnlyDaysAfterReferenceAsFuture() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 18))
        )

        let usage = LLMUsageCalendar(
            entries: [],
            endingAt: reference,
            weekCount: 1,
            calendar: calendar
        )

        let referenceDay = calendar.startOfDay(for: reference)
        XCTAssertEqual(usage.days.first(where: { $0.date == referenceDay })?.isFuture, false)
        XCTAssertTrue(usage.days.filter(\.isFuture).allSatisfy { $0.date > referenceDay })
    }

    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LumenPDFTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("llm-call-log.json")
    }

    private func logEntry(
        startedAt: Date,
        kind: LLMCallKind = .selectionExplanation,
        model: String,
        promptTokens: UInt64,
        completionTokens: UInt64
    ) -> LLMCallLogEntry {
        LLMCallLogEntry(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: startedAt,
            kind: kind,
            model: model,
            baseURL: "https://example.test/v1",
            input: "input",
            output: "output",
            status: .succeeded,
            source: "llm",
            errorMessage: "",
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: promptTokens + completionTokens
        )
    }
}
