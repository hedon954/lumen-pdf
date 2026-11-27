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
    /// 工具栏「文库」打开的书架页。没有打开的 PDF 时，阅读区也会显示书架。
    @Published var browsingLibrary = false
    /// 当前书架。空表示文库根。只在这次运行里记住。
    @Published var shelfParentId: String?
    @Published var shelfPage = ShelfPage(crumbs: [], children: [])

    var showsLibraryShelf: Bool {
        browsingLibrary || (selectedDocument == nil && activeTab == .reader)
    }

    /// 人正在看书架时，新书落在当前层；否则落在文库根上。
    private var importShelfId: String? {
        showsLibraryShelf ? shelfParentId : nil
    }
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
            outlineReadingPosition = nil
            loadKitDocument()
            refreshVocabulary()
            refreshNotes()
            readingActivity.documentChanged(selectedDocument)
        }
    }
    @Published var vocabulary: [VocabularyEntry] = []
    @Published var notes: [NoteEntry] = []
    @Published var activeTab: MainTab = .reader {
        didSet {
            readingActivity.updateFront()
            guard shouldPersistActiveTab else { return }
            restorationStore.updateActiveTab(activeTab.rawValue)
        }
    }
    @Published var toast: ReaderToast?

    /// PDFKit document object – used for TOC sidebar.
    @Published var kitDocument: PDFKit.PDFDocument?
    /// Current page index (0-based), updated on page change for the toolbar and TOC fallback.
    @Published var currentPageIndex: Int = 0
    /// Visible top of the PDF page. The outline uses this, not only the page index.
    @Published var outlineReadingPosition: OutlineReadingPosition?
    /// Normalized vertical scroll (0…1), kept in sync with saves — must not use stale `PdfDocument` after scroll.
    @Published var currentScrollOffset: Double = 0
    /// Total page count of the currently open document (0 = unknown).
    @Published var totalPages: Int = 0

    private let bridge = BridgeService.shared
    private let restorationStore: ReadingRestorationStore
    /// 阅读日志：只在阅读页、窗口在最前面且最近有输入时计时。
    private lazy var readingActivity = ReadingActivityMonitor(
        report: { BridgeService.shared.recordReadingEvent($0) },
        isReaderTabActive: { [weak self] in
            guard let self else { return false }
            return self.activeTab == .reader && !self.showsLibraryShelf
        }
    )
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
        readingActivity.start()
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
        refreshShelf()
    }

    func refreshShelf() {
        shelfPage = (try? bridge.listShelf(parentId: shelfParentId)) ?? ShelfPage(crumbs: [], children: [])
    }

    func openLibrary() {
        browsingLibrary = true
        refreshShelf()
        readingActivity.updateFront()
    }

    /// 回到进文库之前打开的那本，停在当前阅读位置。没有打开的书时仍是文库。
    func showReading() {
        guard selectedDocument != nil else {
            openLibrary()
            return
        }
        browsingLibrary = false
        activeTab = .reader
        readingActivity.updateFront()
    }

    func showSection(_ tab: MainTab) {
        browsingLibrary = false
        activeTab = tab
        readingActivity.updateFront()
    }

    func openShelf(_ id: String) {
        shelfParentId = id
        browsingLibrary = true
        refreshShelf()
    }

    func openShelfCrumb(_ id: String?) {
        shelfParentId = id
        browsingLibrary = true
        refreshShelf()
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
        let existingAtStart = libraryPaths
        let parentShelfId = importShelfId
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
            commitFolderImport(
                collected,
                rootPath: folder.path,
                rootName: folder.lastPathComponent,
                includingSubfolders: includingSubfolders,
                parentShelfId: parentShelfId
            )
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
            if current.matches(path: url.path) {
                showReading()
                return
            }
        }
        // Save a security-scoped bookmark so we can re-open the file after app restart
        // (needed when the app runs in a macOS sandbox).
        saveBookmark(for: url)

        // 复制进 LumenPDF 的书库后打开副本；内容相同的文件复用已有的书。
        guard let imported = try? bridge.importPdfDocument(
            filePath: url.path,
            fileName: url.lastPathComponent
        ) else {
            showToast("无法把这个 PDF 加入文库")
            return
        }
        if imported.isNew {
            try? bridge.placeDocument(id: imported.document.id, parentId: importShelfId)
        }
        selectedDocument = imported.document
        showReading()
        refreshLibrary()
    }

    private func saveBookmark(for url: URL) {
        if let data = LibraryFolderImporter.bookmarkData(for: url) {
            UserDefaults.standard.set(data, forKey: "bm_\(url.path)")
        }
    }

    private func commitFolderImport(
        _ collected: [CollectedLibraryPDF],
        rootPath: String,
        rootName: String,
        includingSubfolders: Bool,
        parentShelfId: String?
    ) {
        let existing = libraryPaths
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

        let tree = LibraryFolderImporter.shelfTree(
            rootPath: rootPath,
            rootName: rootName,
            pdfs: partition.adding,
            includingSubfolders: includingSubfolders
        )
        var addedPaths: [String] = []
        var createdShelfIds: [String] = []
        var reused = 0
        var failed = 0
        importShelfTree(
            tree,
            parentId: parentShelfId,
            bookmarks: bookmarks,
            addedPaths: &addedPaths,
            createdShelfIds: &createdShelfIds,
            reused: &reused,
            failed: &failed
        )
        if !addedPaths.isEmpty || reused > 0 {
            refreshLibrary()
        }
        let message = folderImportToast(
            added: addedPaths.count,
            alreadyPresent: partition.alreadyPresent + reused,
            failed: failed
        )
        if addedPaths.isEmpty {
            showToast(message)
        } else {
            showToast(message) { [weak self] in
                self?.undoFolderImport(paths: addedPaths, shelfIds: createdShelfIds)
            }
        }
    }

    private func importShelfTree(
        _ node: LibraryShelfImportNode,
        parentId: String?,
        bookmarks: [String: Data],
        addedPaths: inout [String],
        createdShelfIds: inout [String],
        reused: inout Int,
        failed: inout Int
    ) {
        guard !node.pdfs.isEmpty || !node.children.isEmpty else { return }
        guard let shelf = try? bridge.createShelf(parentId: parentId, name: node.name) else {
            failed += node.pdfs.count
            return
        }
        createdShelfIds.append(shelf.id)
        for pdf in node.pdfs {
            do {
                let imported = try bridge.importPdfDocument(filePath: pdf.path, fileName: pdf.fileName)
                guard imported.isNew else {
                    reused += 1
                    continue
                }
                try? bridge.placeDocument(id: imported.document.id, parentId: shelf.id)
                if let bookmark = bookmarks[pdf.path] {
                    UserDefaults.standard.set(bookmark, forKey: "bm_\(pdf.path)")
                }
                addedPaths.append(imported.document.filePath)
            } catch {
                failed += 1
            }
        }
        for child in node.children {
            importShelfTree(
                child,
                parentId: shelf.id,
                bookmarks: bookmarks,
                addedPaths: &addedPaths,
                createdShelfIds: &createdShelfIds,
                reused: &reused,
                failed: &failed
            )
        }
    }

    private func undoFolderImport(paths: [String], shelfIds: [String]) {
        let pathSet = Set(paths)
        for path in paths {
            try? bridge.deletePdfDocument(filePath: path)
        }
        for id in shelfIds.reversed() {
            try? bridge.deleteShelfIfEmpty(id: id)
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
        confirmDeleteDocument(doc)
    }

    func confirmClearLibrary() {
        guard let preview = try? bridge.previewLibraryDeletion(), preview.bookCount > 0 else { return }
        confirmDeletion(title: "清空文库？", actionTitle: "清空", preview: preview) { [weak self] in
            guard let self else { return }
            try? self.bridge.deleteLibrary()
            self.shelfParentId = nil
            self.selectedDocument = nil
            self.kitDocument = nil
            self.refreshLibrary()
            self.showToast("已清空文库")
        }
    }

    func confirmDeleteShelf(_ shelf: Shelf) {
        guard let preview = try? bridge.previewShelfDeletion(id: shelf.id) else { return }
        confirmDeletion(title: "删除书架「\(shelf.name)」？", preview: preview) { [weak self] in
            guard let self else { return }
            try? self.bridge.deleteShelf(id: shelf.id)
            self.closeDocuments(preview.documentIds)
            self.refreshLibrary()
        }
    }

    func confirmDeleteDocument(_ document: PdfDocument) {
        guard let preview = try? bridge.previewDocumentDeletion(ids: [document.id]) else { return }
        confirmDeletion(title: "删除「\(document.fileName)」？", preview: preview) { [weak self] in
            guard let self else { return }
            try? self.bridge.deleteDocuments(ids: [document.id])
            self.closeDocuments(preview.documentIds)
            self.refreshLibrary()
        }
    }

    func createShelf(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? bridge.createShelf(parentId: shelfParentId, name: trimmed)
        refreshShelf()
    }

    func renameShelf(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? bridge.renameShelf(id: id, name: trimmed)
        refreshShelf()
    }

    func moveShelfItem(kind: ShelfItemKind, id: String, toParent parentId: String?) {
        switch kind {
        case .shelf:
            try? bridge.moveShelf(id: id, parentId: parentId)
        case .document:
            try? bridge.moveDocument(id: id, parentId: parentId)
        }
        refreshLibrary()
    }

    func reorderShelf(to children: [ShelfChild]) {
        let order = children.map { child in
            switch child {
            case .shelf(let shelf):
                return ShelfPlacement(kind: .shelf, id: shelf.id)
            case .document(let document):
                return ShelfPlacement(kind: .document, id: document.id)
            }
        }
        try? bridge.reorderShelf(parentId: shelfParentId, order: order)
        refreshShelf()
    }

    private func confirmDeletion(
        title: String,
        actionTitle: String = "删除",
        preview: DeletionPreview,
        perform: () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = deletionMessage(preview)
        alert.alertStyle = .warning
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform()
    }

    private func deletionMessage(_ preview: DeletionPreview) -> String {
        "\(preview.bookCount) 本 PDF 会从文库移出，书库副本会删除。这 \(preview.bookCount) 本书的 \(preview.noteCount) 条笔记会删除，\(preview.vocabularyContextCount) 条单词语境会删除。同一单词在其他书里的语境会保留。原来的文件还在。"
    }

    private func closeDocuments(_ ids: [String]) {
        guard let selected = selectedDocument, ids.contains(selected.id) else { return }
        selectedDocument = nil
        kitDocument = nil
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) {
        try? bridge.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
        guard selectedDocument?.filePath == filePath else { return }
        currentPageIndex = Int(page)
        currentScrollOffset = scrollOffset
        // Do not refreshLibrary() here — it is expensive and can fight with PDF restore.
    }

    func updateOutlineReadingPosition(page: Int, topY: Double) {
        let next = OutlineReadingPosition(pageIndex: page, topY: topY)
        guard outlineReadingPosition != next else { return }
        outlineReadingPosition = next
    }

    // MARK: - Private

    private func loadKitDocument() {
        guard let filePath = selectedDocument?.filePath else {
            kitDocument = nil
            return
        }
        kitDocument = PDFKitView.loadDocument(filePath: filePath)
    }

    /// 文库里每本书的副本路径和原文件路径，用于判断文件是否已在文库中。
    private var libraryPaths: Set<String> {
        Set(library.flatMap { [$0.filePath] + ($0.originalPath.map { [$0] } ?? []) })
    }

    private func restoreLastDocument() {
        // 迁移进书库之前记下的是原文件路径。
        guard let path = restorationStore.state.lastOpenedFilePath,
              let doc = library.first(where: { $0.matches(path: path) }) else { return }
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
        if let doc = library.first(where: { $0.matches(path: filePath) }) {
            selectedDocument = doc
            showReading()
        } else {
            openPDF(url: URL(fileURLWithPath: filePath))
            guard selectedDocument?.matches(path: filePath) == true else { return }
        }
        // 重新导入后打开的是书库副本，跳页要用副本的路径。
        guard let openedPath = selectedDocument?.filePath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            ReaderEventBus.shared.postJumpToPage(page: page, filePath: openedPath)
        }
    }
}
