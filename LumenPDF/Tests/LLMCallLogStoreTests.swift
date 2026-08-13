import XCTest
@testable import LumenPDF

@MainActor
final class LLMCallLogStoreTests: XCTestCase {
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

    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LumenPDFTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("llm-call-log.json")
    }
}
