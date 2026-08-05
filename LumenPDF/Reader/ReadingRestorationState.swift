import AppKit
import Combine
import Foundation

struct ReadingRestorationState: Codable, Equatable {
    struct WindowFrame: Codable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(_ frame: NSRect) {
            x = Double(frame.origin.x)
            y = Double(frame.origin.y)
            width = Double(frame.size.width)
            height = Double(frame.size.height)
        }

        var nsRect: NSRect {
            NSRect(x: x, y: y, width: width, height: height)
        }
    }

    struct Sidebar: Codable, Equatable {
        var isVisible: Bool
        var width: Double
    }

    struct Inspector: Codable, Equatable {
        var isVisible: Bool
        var width: Double
        var mode: String
    }

    struct PDFViewport: Codable, Equatable {
        /// Top-left corner of the visible reading area, expressed in the coordinate space of
        /// one page.
        ///
        /// The normalized offsets below are fractions of the document layout that existed when
        /// they were captured, so they point somewhere else as soon as PDFKit re-fits the
        /// document at another scale — which is exactly what happens while the window frame and
        /// split widths are still being restored. A page anchor is independent of scale, so it
        /// stays on the same line of text.
        struct PageAnchor: Codable, Equatable {
            var pageIndex: Int
            var x: Double
            var y: Double

            var isValid: Bool {
                pageIndex >= 0 && x.isFinite && y.isFinite
            }
        }

        var pageIndex: Int?
        var autoScales: Bool
        var scaleFactor: Double
        var horizontalOffset: Double
        var verticalOffset: Double
        /// Absent for viewports saved before anchors existed; the normalized offsets are the
        /// fallback in that case.
        var anchor: PageAnchor?
    }

    static let currentVersion = 1
    static let defaultOutlineWidth = 220.0
    static let minimumOutlineWidth = 200.0
    static let maximumOutlineWidth = 420.0
    static let defaultInspectorWidth = 360.0
    static let minimumInspectorWidth = 300.0
    static let maximumInspectorWidth = 460.0

    var version: Int
    var windowFrame: WindowFrame?
    var outlineSidebar: Sidebar
    var inspector: Inspector
    var activeTab: String
    var lastOpenedFilePath: String?
    var pdfViewports: [String: PDFViewport]

    static let defaultValue = ReadingRestorationState(
        version: currentVersion,
        windowFrame: nil,
        outlineSidebar: Sidebar(isVisible: true, width: defaultOutlineWidth),
        inspector: Inspector(isVisible: true, width: defaultInspectorWidth, mode: "words"),
        activeTab: "reader",
        lastOpenedFilePath: nil,
        pdfViewports: [:]
    )
}

/// Single source of truth for stable state that defines the user's reading workspace.
///
/// Transient presentation state such as selections, action bars, editors, and loading
/// overlays deliberately stays outside this store.
final class ReadingRestorationStore: ObservableObject {
    static let shared = ReadingRestorationStore()

    @Published private(set) var state: ReadingRestorationState
    @Published private(set) var isRestoringLayout = true

    private let defaults: UserDefaults
    private let storageKey = "reading_restoration_state_v1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(ReadingRestorationState.self, from: data),
           stored.version == ReadingRestorationState.currentVersion {
            state = Self.sanitized(stored)
        } else {
            state = Self.migrateLegacyState(from: defaults)
            persist()
        }
    }

    /// Freezes split-width capture while the window is being attached, minimized,
    /// restored, or torn down. Transient AppKit layout passes must never replace
    /// the last width that was measured while the window was visible and stable.
    func beginLayoutRestoration() {
        guard !isRestoringLayout else { return }
        isRestoringLayout = true
    }

    func finishLayoutRestoration() {
        guard isRestoringLayout else { return }
        isRestoringLayout = false
    }

    func updateWindowFrame(_ frame: NSRect) {
        update { $0.windowFrame = .init(frame) }
    }

    func updateOutlineVisibility(_ isVisible: Bool) {
        update { $0.outlineSidebar.isVisible = isVisible }
    }

    func updateOutlineWidth(_ width: Double) {
        guard !isRestoringLayout else { return }
        update {
            $0.outlineSidebar.width = Self.clamp(
                width,
                minimum: ReadingRestorationState.minimumOutlineWidth,
                maximum: ReadingRestorationState.maximumOutlineWidth
            )
        }
    }

    func updateInspectorVisibility(_ isVisible: Bool) {
        update { $0.inspector.isVisible = isVisible }
    }

    func updateInspectorWidth(_ width: Double) {
        guard !isRestoringLayout else { return }
        update {
            $0.inspector.width = Self.clamp(
                width,
                minimum: ReadingRestorationState.minimumInspectorWidth,
                maximum: ReadingRestorationState.maximumInspectorWidth
            )
        }
    }

    func updateInspectorMode(_ mode: String) {
        update { $0.inspector.mode = mode }
    }

    func updateActiveTab(_ activeTab: String) {
        update { $0.activeTab = activeTab }
    }

    func updateLastOpenedFilePath(_ filePath: String?) {
        update { $0.lastOpenedFilePath = filePath }
    }

    func viewport(for filePath: String) -> ReadingRestorationState.PDFViewport? {
        state.pdfViewports[filePath]
    }

    func updateViewport(_ viewport: ReadingRestorationState.PDFViewport, for filePath: String) {
        guard viewport.scaleFactor.isFinite,
              viewport.scaleFactor > 0,
              viewport.horizontalOffset.isFinite,
              viewport.verticalOffset.isFinite else { return }
        update { $0.pdfViewports[filePath] = viewport }
    }

    private func update(_ mutation: (inout ReadingRestorationState) -> Void) {
        var next = state
        mutation(&next)
        next = Self.sanitized(next)
        guard next != state else { return }
        state = next
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func sanitized(_ state: ReadingRestorationState) -> ReadingRestorationState {
        var state = state
        state.outlineSidebar.width = clamp(
            state.outlineSidebar.width,
            minimum: ReadingRestorationState.minimumOutlineWidth,
            maximum: ReadingRestorationState.maximumOutlineWidth
        )
        state.inspector.width = clamp(
            state.inspector.width,
            minimum: ReadingRestorationState.minimumInspectorWidth,
            maximum: ReadingRestorationState.maximumInspectorWidth
        )
        state.pdfViewports = state.pdfViewports.compactMapValues(sanitizedViewport)
        return state
    }

    private static func sanitizedViewport(
        _ viewport: ReadingRestorationState.PDFViewport
    ) -> ReadingRestorationState.PDFViewport? {
        guard viewport.scaleFactor.isFinite,
              viewport.scaleFactor > 0,
              viewport.horizontalOffset.isFinite,
              viewport.verticalOffset.isFinite else { return nil }
        var result = viewport
        if result.anchor?.isValid == false {
            result.anchor = nil
        }
        return result
    }

    private static func migrateLegacyState(from defaults: UserDefaults) -> ReadingRestorationState {
        var state = ReadingRestorationState.defaultValue

        if let savedFrame = defaults.string(forKey: "main_window_frame") {
            let frame = NSRectFromString(savedFrame)
            if !frame.isEmpty {
                state.windowFrame = .init(frame)
            }
        }

        if defaults.object(forKey: "show_outline_sidebar") != nil {
            state.outlineSidebar.isVisible = defaults.bool(forKey: "show_outline_sidebar")
        }
        let outlineWidth = defaults.double(forKey: "outline_sidebar_width")
        if outlineWidth > 0 {
            state.outlineSidebar.width = outlineWidth
        }

        if defaults.object(forKey: "show_reading_inspector") != nil {
            state.inspector.isVisible = defaults.bool(forKey: "show_reading_inspector")
        }
        let inspectorWidth = defaults.double(forKey: "reading_inspector_width")
        if inspectorWidth > 0 {
            state.inspector.width = inspectorWidth
        }
        if let inspectorMode = defaults.string(forKey: "reading_inspector_mode") {
            state.inspector.mode = inspectorMode
        }

        if let activeTab = defaults.string(forKey: "main_active_tab") {
            state.activeTab = activeTab
        }
        state.lastOpenedFilePath = defaults.string(forKey: "lastOpenedFilePath")

        let viewportPrefix = "pdf_viewport_state_"
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(viewportPrefix) {
            guard let data = value as? Data,
                  let viewport = try? JSONDecoder().decode(
                      ReadingRestorationState.PDFViewport.self,
                      from: data
                  ) else { continue }
            let filePath = String(key.dropFirst(viewportPrefix.count))
            state.pdfViewports[filePath] = viewport
        }

        return sanitized(state)
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite else { return minimum }
        return min(max(value, minimum), maximum)
    }
}
