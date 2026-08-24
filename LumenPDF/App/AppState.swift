import Foundation
import AppKit
import PDFKit
import Combine

enum MainTab: String { case reader, vocabulary, notes }

@MainActor
final class AppState: ObservableObject {
    @Published var library: [PdfDocument] = []
    @Published var selectedDocument: PdfDocument? {
        didSet {
            // Persist last opened file path for auto-restore on launch
            if let path = selectedDocument?.filePath {
                restorationStore.updateLastOpenedFilePath(path)
            }
            // Pre-set currentPageIndex from the stored lastPage so the TOC can
            // scroll to the correct chapter immediately, before the PDF finishes loading.
            if let doc = selectedDocument {
                currentPageIndex = Int(doc.lastPage)
                currentScrollOffset = doc.lastScrollOffset
                totalPages = Int(doc.totalPages)
            } else {
                currentPageIndex = 0
                currentScrollOffset = 0
                totalPages = 0
            }
            loadKitDocument()
            refreshVocabulary()
            refreshNotes()
        }
    }
    @Published var vocabulary: [VocabularyEntry] = []
    @Published var notes: [NoteEntry] = []
    @Published var activeTab: MainTab = .reader {
        didSet {
            guard shouldPersistActiveTab else { return }
            restorationStore.updateActiveTab(activeTab.rawValue)
        }
    }
    @Published var toastMessage: String?

    /// PDFKit document object – used for TOC sidebar.
    @Published var kitDocument: PDFKit.PDFDocument?
    /// Current page index (0-based), updated on page change for TOC highlight.
    @Published var currentPageIndex: Int = 0
    /// Normalized vertical scroll (0…1), kept in sync with saves — must not use stale `PdfDocument` after scroll.
    @Published var currentScrollOffset: Double = 0
    /// Total page count of the currently open document (0 = unknown).
    @Published var totalPages: Int = 0

    private let bridge = BridgeService.shared
    private let restorationStore: ReadingRestorationStore
    private var shouldPersistActiveTab = true

    init(restorationStore: ReadingRestorationStore = .shared) {
        self.restorationStore = restorationStore
        let promptUpdateResult =
            PromptTemplateUpdateCoordinator.shared.applyUpdatesAtLaunch()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-vocabulary") {
            shouldPersistActiveTab = false
            activeTab = .vocabulary
        } else if args.contains("--uitesting-notes") {
            shouldPersistActiveTab = false
            activeTab = .notes
        } else if let tab = MainTab(rawValue: restorationStore.state.activeTab) {
            activeTab = tab
        }

        bridge.initializeIfNeeded()
        refreshLibrary()
        restoreLastDocument()

        if !promptUpdateResult.pendingCustomLanguages.isEmpty {
            showToast("系统提示词已有更新；你的自定义模板未被覆盖，请在设置中处理")
        } else if !promptUpdateResult.automaticallyUpdatedLanguages.isEmpty {
            showToast("系统提示词已更新，未修改的模板已自动升级")
        }
    }

    // MARK: - Library

    func refreshLibrary() {
        library = (try? bridge.listPdfDocuments()) ?? []
    }

    func refreshVocabulary() {
        vocabulary = (try? bridge.listVocabulary()) ?? []
    }

    func refreshNotes() {
        notes = (try? bridge.listNotes()) ?? []
    }

    @discardableResult
    func saveNoteItem(noteId: String, itemIndex: Int, text: String) -> Bool {
        guard let note = notes.first(where: { $0.id == noteId }),
              let updated = NoteTextList.replacingItem(at: itemIndex, with: text, from: note.note),
              (try? BridgeService.shared.updateNote(id: noteId, note: updated)) != nil
        else {
            return false
        }
        refreshNotes()
        return true
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPDF(url: url)
    }

    func openPDF(url: URL) {
        // Save a security-scoped bookmark so we can re-open the file after app restart
        // (needed when the app runs in a macOS sandbox).
        saveBookmark(for: url)

        guard let doc = try? bridge.upsertPdfDocument(
            filePath: url.path,
            fileName: url.lastPathComponent,
            totalPages: 0
        ) else { return }
        selectedDocument = doc
        refreshLibrary()
    }

    private func saveBookmark(for url: URL) {
        // Try security-scoped bookmark first; fall back to plain bookmark.
        let data = (try? url.bookmarkData(options: .withSecurityScope,
                                          includingResourceValuesForKeys: nil,
                                          relativeTo: nil))
                ?? (try? url.bookmarkData())
        if let data {
            UserDefaults.standard.set(data, forKey: "bm_\(url.path)")
        }
    }

    func removeFromLibrary(_ doc: PdfDocument) {
        try? bridge.deletePdfDocument(filePath: doc.filePath)
        if selectedDocument?.id == doc.id {
            selectedDocument = nil
            kitDocument = nil
        }
        refreshLibrary()
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) {
        try? bridge.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
        currentPageIndex = Int(page)
        currentScrollOffset = scrollOffset
        // Do not refreshLibrary() here — it is expensive and can fight with PDF restore.
    }

    // MARK: - Private

    private func loadKitDocument() {
        guard let filePath = selectedDocument?.filePath else {
            kitDocument = nil
            return
        }
        kitDocument = PDFKitView.loadDocument(filePath: filePath)
    }

    private func restoreLastDocument() {
        guard let path = restorationStore.state.lastOpenedFilePath,
              let doc = library.first(where: { $0.filePath == path }) else { return }
        selectedDocument = doc
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.toastMessage = nil
        }
    }

    func openLibraryDocument(filePath: String, page: Int) {
        guard let doc = library.first(where: { $0.filePath == filePath }) else { return }
        selectedDocument = doc
        activeTab = .reader
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            ReaderEventBus.shared.postJumpToPage(page: page, filePath: filePath)
        }
    }
}
