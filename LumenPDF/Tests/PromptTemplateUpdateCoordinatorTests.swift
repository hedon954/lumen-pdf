import XCTest
@testable import LumenPDF

final class PromptTemplateUpdateCoordinatorTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PromptTemplateUpdateCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCustomActiveTemplateIsNotOverwritten() {
        defaults.set("简体中文", forKey: "target_language")
        defaults.set("CUSTOM WORD PROMPT", forKey: "word_prompt_template")
        defaults.set(
            PromptTemplateDefaults.legacyWordChineseWithEmbeddedEtymology,
            forKey: "word_prompt_template_zh"
        )

        let result = PromptTemplateUpdateCoordinator(defaults: defaults)
            .applyUpdatesAtLaunch()

        XCTAssertEqual(
            defaults.string(forKey: "word_prompt_template"),
            "CUSTOM WORD PROMPT"
        )
        XCTAssertEqual(
            defaults.string(forKey: "word_prompt_template_zh"),
            "CUSTOM WORD PROMPT"
        )
        XCTAssertTrue(defaults.bool(forKey: "word_prompt_template_update_pending_zh"))
        XCTAssertEqual(defaults.integer(forKey: "word_prompt_template_revision_zh"), 0)
        XCTAssertEqual(result.pendingCustomLanguages, ["简体中文"])
    }

    func testKnownBuiltInTemplateUpdatesAutomatically() {
        defaults.set("简体中文", forKey: "target_language")
        defaults.set(
            PromptTemplateDefaults.legacyWordChineseWithEmbeddedEtymology,
            forKey: "word_prompt_template"
        )

        let result = PromptTemplateUpdateCoordinator(defaults: defaults)
            .applyUpdatesAtLaunch()

        XCTAssertEqual(
            defaults.string(forKey: "word_prompt_template"),
            PromptTemplateDefaults.wordChinese
        )
        XCTAssertEqual(
            defaults.integer(forKey: "word_prompt_template_revision_zh"),
            PromptTemplateDefaults.wordTemplateRevision
        )
        XCTAssertFalse(defaults.bool(forKey: "word_prompt_template_update_pending_zh"))
        XCTAssertEqual(result.automaticallyUpdatedLanguages, ["简体中文"])
    }

    func testKeepingCustomTemplateStopsRepeatedReminderForCurrentRevision() {
        defaults.set("简体中文", forKey: "target_language")
        defaults.set("CUSTOM WORD PROMPT", forKey: "word_prompt_template")
        let coordinator = PromptTemplateUpdateCoordinator(defaults: defaults)

        _ = coordinator.applyUpdatesAtLaunch()
        coordinator.keepCurrentTemplate(for: "简体中文")
        let nextLaunch = coordinator.applyUpdatesAtLaunch()

        XCTAssertEqual(
            defaults.string(forKey: "word_prompt_template"),
            "CUSTOM WORD PROMPT"
        )
        XCTAssertFalse(coordinator.hasPendingUpdate(for: "简体中文"))
        XCTAssertTrue(nextLaunch.pendingCustomLanguages.isEmpty)
    }
}
