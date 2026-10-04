import Foundation
import AppKit
import PDFKit
import Combine

enum MainTab: String { case reader, vocabulary, notes }

struct ReaderToast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
}

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
    @Published var toast: ReaderToast?

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
    func saveNoteItem(
        noteId: String, itemIndex: Int, text: String,
        expectedText: String? = nil, expectedCount: Int? = nil
    ) -> Bool {
        guard let note = notes.first(where: { $0.id == noteId }),
              let updated = NoteTextList.replacingItem(
                at: itemIndex, with: text, from: note.note,
                expectedText: expectedText, expectedCount: expectedCount
              ),
              (try? ReaderPersistence.shared.updateNote(id: noteId, note: updated)) != nil
        else {
            return false
        }
        refreshNotes()
        return true
    }

    @discardableResult
    func appendNoteItem(noteId: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let note = notes.first(where: { $0.id == noteId }) else { return false }
        let updated = NoteTextList.encode(NoteTextList.decode(note.note) + [trimmed])
        do {
            try ReaderPersistence.shared.updateNote(id: noteId, note: updated)
            refreshNotes()
            return true
        } catch {
            return false
        }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPDF(url: url)
    }

    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "导入"
        let includeSubfolders = NSButton(checkboxWithTitle: "包含子文件夹", target: nil, action: nil)
        includeSubfolders.state = .off
        includeSubfolders.sizeToFit()
        includeSubfolders.frame.size.height = max(includeSubfolders.frame.height, 22)
        panel.accessoryView = includeSubfolders
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        importPDFs(in: folder, includingSubfolders: includeSubfolders.state == .on)
    }

    private func importPDFs(in folder: URL, includingSubfolders: Bool) {
        let accessing = folder.startAccessingSecurityScopedResource()
        let existingAtStart = Set(library.map(\.filePath))
        Task {
            defer {
                if accessing { folder.stopAccessingSecurityScopedResource() }
            }
            let collected = await Task.detached(priority: .userInitiated) {
                LibraryFolderImporter.collectPDFs(
                    in: folder,
                    existingPaths: existingAtStart,
                    includingSubfolders: includingSubfolders
                )
            }.value
            commitFolderImport(collected)
        }
    }

    func openPDF(url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard PDFKit.PDFDocument(url: url) != nil else {
            showToast("无法打开这个 PDF 文件")
            return
        }
        if let current = selectedDocument {
            ReaderEventBus.shared.postSaveReadingPositionNow(filePath: current.filePath)
            if current.filePath == url.path {
                activeTab = .reader
                return
            }
        }
        // Save a security-scoped bookmark so we can re-open the file after app restart
        // (needed when the app runs in a macOS sandbox).
        saveBookmark(for: url)

        guard let doc = try? bridge.upsertPdfDocument(
            filePath: url.path,
            fileName: url.lastPathComponent,
            totalPages: 0
        ) else { return }
        selectedDocument = doc
        activeTab = .reader
        refreshLibrary()
    }

    private func saveBookmark(for url: URL) {
        if let data = LibraryFolderImporter.bookmarkData(for: url) {
            UserDefaults.standard.set(data, forKey: "bm_\(url.path)")
        }
    }

    private func commitFolderImport(_ collected: [CollectedLibraryPDF]) {
        let existing = Set(library.map(\.filePath))
        let partition = LibraryFolderImporter.partition(
            collected.map(\.pdf),
            existingPaths: existing
        )
        var bookmarks: [String: Data] = [:]
        for item in collected {
            if let bookmark = item.bookmark {
                bookmarks[item.pdf.path] = bookmark
            }
        }

        var addedPaths: [String] = []
        var failed = 0
        for pdf in partition.adding {
            do {
                _ = try bridge.upsertPdfDocument(
                    filePath: pdf.path,
                    fileName: pdf.fileName,
                    totalPages: 0
                )
                if let bookmark = bookmarks[pdf.path] {
                    UserDefaults.standard.set(bookmark, forKey: "bm_\(pdf.path)")
                }
                addedPaths.append(pdf.path)
            } catch {
                failed += 1
            }
        }
        if !addedPaths.isEmpty {
            refreshLibrary()
        }
        let message = folderImportToast(
            added: addedPaths.count,
            alreadyPresent: partition.alreadyPresent,
            failed: failed
        )
        if addedPaths.isEmpty {
            showToast(message)
        } else {
            showToast(message) { [weak self] in
                self?.undoFolderImport(paths: addedPaths)
            }
        }
    }

    private func undoFolderImport(paths: [String]) {
        let pathSet = Set(paths)
        for path in paths {
            try? bridge.deletePdfDocument(filePath: path)
        }
        if let selected = selectedDocument, pathSet.contains(selected.filePath) {
            selectedDocument = nil
            kitDocument = nil
        }
        refreshLibrary()
        showToast("已撤回导入")
    }

    private func folderImportToast(added: Int, alreadyPresent: Int, failed: Int) -> String {
        if added == 0 && alreadyPresent == 0 && failed == 0 {
            return "这个文件夹里没有 PDF"
        }
        if added == 0 && failed == 0 {
            return "这些 PDF 已在文库中"
        }
        var parts: [String] = []
        if added > 0 {
            parts.append("已加入 \(added) 个 PDF")
        }
        if alreadyPresent > 0 {
            parts.append("\(alreadyPresent) 个已在文库中")
        }
        if failed > 0 {
            parts.append("\(failed) 个未能加入")
        }
        return parts.joined(separator: "，")
    }

    func removeFromLibrary(_ doc: PdfDocument) {
        try? bridge.deletePdfDocument(filePath: doc.filePath)
        if selectedDocument?.id == doc.id {
            selectedDocument = nil
            kitDocument = nil
        }
        refreshLibrary()
    }

    func confirmClearLibrary() {
        guard !library.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "清空文库？"
        alert.informativeText = "PDF 会从文库移出。笔记、单词和磁盘上的文件都会保留。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearLibrary()
    }

    private func clearLibrary() {
        for doc in library {
            try? bridge.deletePdfDocument(filePath: doc.filePath)
        }
        selectedDocument = nil
        kitDocument = nil
        refreshLibrary()
        showToast("已清空文库")
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) {
        try? bridge.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
        guard selectedDocument?.filePath == filePath else { return }
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

    func showToast(_ message: String, undo: (() -> Void)? = nil) {
        let next = ReaderToast(message: message, undo: undo)
        toast = next
        let duration: TimeInterval = undo == nil ? 2.5 : 8
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard self?.toast?.id == next.id else { return }
            self?.toast = nil
        }
    }

    func openLibraryDocument(filePath: String, page: Int) {
        if let doc = library.first(where: { $0.filePath == filePath }) {
            selectedDocument = doc
            activeTab = .reader
        } else {
            openPDF(url: URL(fileURLWithPath: filePath))
            guard selectedDocument?.filePath == filePath else { return }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            ReaderEventBus.shared.postJumpToPage(page: page, filePath: filePath)
        }
    }
}
