import AppKit
import SwiftUI
import XCTest
@testable import LumenPDF

@MainActor
final class ReadingPopoverLayoutTests: XCTestCase {
    func testLongPhoneticHeaderAndSharedChromeInBothAppearances() async throws {
        let rect = CGRect(x: 640, y: 185, width: 100, height: 26)
        let result = TranslationResult(
            word: "implement", phonetic: "/ˈɪmplɪmənt/（名词）或 /ˈɪmplɪment/（动词）",
            partOfSpeech: "verb", contextTranslation: "工具；器具；实施；执行",
            contextExplanation: "将计划或方法付诸实施。", etymology: "源自拉丁语 implēre。",
            generalDefinition: "to put a plan into effect", contextSentenceTranslation: "我们实现一个文本生成函数。",
            source: "llm", llmErrorMessage: "", fallbackErrorMessage: "", isCompleteFailure: false,
            sentenceBreakdown: [], promptTokens: 0, completionTokens: 0, totalTokens: 0, httpRequest: ""
        )
        let request = TranslationBubbleRequest(
            pdfPath: "/tmp/layout.pdf", pdfName: "layout.pdf", word: "implement", sentence: "implement",
            sentenceHash: "layout", bounds: rect, boundsStr: "", page: 0,
            selectionAnchorRect: rect, result: result
        )
        for dark in [false, true] {
            let content = TranslationBubble(
                request: request, isLoading: false, availableSize: CGSize(width: 900, height: 700),
                overlayAnchorRect: rect, onSave: { _ in nil }, onDelete: { _, _ in },
                onExplain: {}, onRetry: {}, onDismiss: {}
            )
            try await render(content, name: "translation-\(dark ? "dark" : "light")", dark: dark)
            let draft = UnderlineNoteDraft(
                word: "Before we implement a text generation function", boundsStr: "", page: 0,
                pageMarkups: [], anchor: .zero, anchorRect: rect, appendingNoteId: nil, existingNoteText: ""
            )
            try await render(UnderlineNoteDraftView(
                draft: draft, availableSize: CGSize(width: 900, height: 700), overlayAnchorRect: rect,
                onCancel: {}, onSave: { _ in }
            ), name: "note-\(dark ? "dark" : "light")", dark: dark)
        }
    }

    private func render<Content: View>(_ content: Content, name: String, dark: Bool) async throws {
        let host = NSHostingView(rootView: ZStack {
            Color(nsColor: .windowBackgroundColor)
            content
        }.environment(\.colorScheme, dark ? .dark : .light).frame(width: 900, height: 700))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.layoutSubtreeIfNeeded()
        // Capture the actual SwiftUI/AppKit drawing for visual regression review.
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/lumen-popover-layout")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        XCTAssertEqual(host.bounds.size, CGSize(width: 900, height: 700))
    }
}
