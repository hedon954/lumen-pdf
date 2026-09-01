import SwiftUI
import PDFKit
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLibrary = false
    @State private var showSetupSheet = false
    @State private var inspectorTransitionID: UUID?
    @StateObject private var inspectorModel = ReadingInspectorModel()
    @StateObject private var selectionActionBarModel = SelectionActionBarModel()
    @StateObject private var translationOverlayModel = TranslationOverlayModel()
    @StateObject private var viewportTransitionController = ReaderViewportTransitionController()
    @StateObject private var workspaceSearch = WorkspaceSearchController()
    @ObservedObject private var restorationStore = ReadingRestorationStore.shared
    @AppStorage("llm_base_url") private var baseURL = ""
    @AppStorage("llm_model") private var model = ""

    var body: some View {
        NavigationSplitView(columnVisibility: outlineColumnVisibility) {
            // Left sidebar: PDF outline TOC (only when a document is open)
            Group {
                if let kitDoc = appState.kitDocument {
                    PDFOutlineSidebarView(document: kitDoc)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("打开 PDF 后\n显示目录")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(
                min: restorationStore.isRestoringLayout
                    ? clampedOutlineSidebarWidth
                    : Self.minimumOutlineSidebarWidth,
                ideal: clampedOutlineSidebarWidth,
                max: restorationStore.isRestoringLayout
                    ? clampedOutlineSidebarWidth
                    : Self.maximumOutlineSidebarWidth
            )
            .background {
                SplitPaneWidthObserver(
                    edge: .leading,
                    restoredWidth: clampedOutlineSidebarWidth,
                    isRestoring: restorationStore.isRestoringLayout
                ) { width in
                    guard isOutlineSidebarVisible else { return }
                    restorationStore.updateOutlineWidth(Double(width))
                }
            }
        } detail: {
            ZStack(alignment: .bottom) {
                // Keep PDFReaderView alive (never destroyed on tab switch),
                // so scroll position is preserved.
                if let doc = appState.selectedDocument {
                    ReadingWorkspaceView(
                        document: doc,
                        inspectorModel: inspectorModel,
                        selectionActionBarModel: selectionActionBarModel,
                        translationOverlayModel: translationOverlayModel,
                        viewportTransitionController: viewportTransitionController,
                        setInspectorVisible: setReadingInspectorVisible
                    )
                    .opacity(appState.activeTab == .reader ? 1 : 0)
                    .allowsHitTesting(appState.activeTab == .reader)
                } else if appState.activeTab == .reader {
                    EmptyStateView()
                }

                if appState.activeTab == .vocabulary {
                    VocabularyListView()
                }

                if appState.activeTab == .notes {
                    NoteListView()
                }

                if let msg = appState.toastMessage {
                    ToastView(message: msg)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: appState.toastMessage)
                }
            }
        }
        .coordinateSpace(name: ReaderRootCoordinateSpace.name)
        .overlay {
            if appState.activeTab == .reader {
                SelectionActionBarOverlay(model: selectionActionBarModel)
            }
        }
        .overlay {
            if appState.activeTab == .reader,
               let request = translationOverlayModel.request
            {
                GeometryReader { proxy in
                    TranslationBubble(
                        request: request,
                        isLoading: translationOverlayModel.isLoading,
                        availableSize: proxy.size,
                        overlayAnchorRect: ReaderRootCoordinateSpace.localRect(
                            request.selectionAnchorRect,
                            overlayFrameInRoot: proxy.frame(
                                in: .named(ReaderRootCoordinateSpace.name)
                            )
                        ),
                        onSave: { result in
                            saveTranslation(result: result, request: request)
                        },
                        onDelete: { id, savedToNote in
                            deleteTranslationSave(
                                id: id,
                                savedToNote: savedToNote,
                                request: request
                            )
                        },
                        onExplain: {
                            startGuideFromTranslation(request)
                        },
                        onRetry: translationOverlayModel.retry,
                        onDismiss: translationOverlayModel.dismiss
                    )
                }
            }
        }
        .blur(radius: workspaceSearch.isPresented ? 4 : 0)
        .overlay {
            ZStack {
                if workspaceSearch.isPresented {
                    WorkspaceSearchOverlay(controller: workspaceSearch) { hit in
                        let query = workspaceSearch.query
                        workspaceSearch.dismiss()
                        WorkspaceSearchOpener.open(
                            hit,
                            query: query,
                            appState: appState,
                            inspectorModel: inspectorModel,
                            setInspectorVisible: setReadingInspectorVisible
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeOut(duration: 0.16), value: workspaceSearch.isPresented)
        }
        .toolbar {
            // Left: Library picker
            ToolbarItem(placement: .navigation) {
                Button {
                    showLibrary.toggle()
                } label: {
                    Label("文库", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("toolbar.library")
                .popover(isPresented: $showLibrary, arrowEdge: .bottom) {
                    LibraryPickerView()
                        .frame(width: 320, height: 360)
                }
            }

            // Center: Tab switcher + filename + page indicator
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Picker("", selection: $appState.activeTab) {
                        Text("PDF 阅读").tag(MainTab.reader)
                        Text("单词本").tag(MainTab.vocabulary)
                        Text("笔记").tag(MainTab.notes)
                    }
                    .accessibilityIdentifier("toolbar.mainTabs")
                    .pickerStyle(.segmented)
                    .frame(width: 280)

                    // O8: Always show filename when a document is selected (not just in reader mode)
                    if let fileName = appState.selectedDocument?.fileName {
                        Divider().frame(height: 14)

                        Text(fileName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()

                        // Page indicator only in reader mode
                        if appState.activeTab == .reader && appState.totalPages > 0 {
                            Text("\(appState.currentPageIndex + 1) / \(appState.totalPages)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .animation(.none, value: appState.currentPageIndex)
                        }
                    }
                }
            }

            // Right: Open file + Settings
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    presentWorkspaceSearch()
                } label: {
                    Label("查找", systemImage: "magnifyingglass")
                }
                .help("查找…")
                .accessibilityIdentifier("toolbar.workspaceSearch")

                if appState.activeTab == .reader && appState.selectedDocument != nil {
                    Button {
                        setReadingInspectorVisible(!inspectorModel.isVisible)
                    } label: {
                        Label(
                            inspectorModel.isVisible ? "隐藏阅读 Inspector" : "显示阅读 Inspector",
                            systemImage: "sidebar.right"
                        )
                    }
                    .accessibilityIdentifier("toolbar.readingInspector")
                }

                Button {
                    appState.openFilePicker()
                } label: {
                    Label("打开 PDF", systemImage: "plus")
                }
                .accessibilityIdentifier("toolbar.openPDF")

                if #available(macOS 14, *) {
                    SettingsLink {
                        Label("设置", systemImage: "gear")
                    }
                    .accessibilityIdentifier("toolbar.settings")
                } else {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Label("设置", systemImage: "gear")
                    }
                    .accessibilityIdentifier("toolbar.settings")
                }
            }
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--uitesting-show-settings") {
                showSetupSheet = true
                return
            }
            guard !args.contains("--uitesting") else { return }
            // Show LLM setup sheet if not configured (and user didn't opt "never remind")
            if baseURL.isEmpty || model.isEmpty {
                showSetupSheet = true
                return
            }
            let storedKey = KeychainService.loadLLMAPIKey(
                for: SettingsRuntimeService.shared.normalizedLLMBaseURL(baseURL)
            ) ?? ""
            if storedKey.isEmpty {
                showSetupSheet = true
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            SettingsView(onDismiss: { showSetupSheet = false })
        }
        .onChange(of: appState.activeTab) { _, _ in
            selectionActionBarModel.dismiss()
            translationOverlayModel.dismiss()
        }
        .onChange(of: appState.selectedDocument?.id) { _, _ in
            selectionActionBarModel.dismiss()
            translationOverlayModel.dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentWorkspaceSearch)) { _ in
            presentWorkspaceSearch()
        }
    }

    private static let minimumOutlineSidebarWidth = CGFloat(
        ReadingRestorationState.minimumOutlineWidth
    )
    private static let maximumOutlineSidebarWidth = CGFloat(
        ReadingRestorationState.maximumOutlineWidth
    )

    private var isOutlineSidebarVisible: Bool {
        restorationStore.state.outlineSidebar.isVisible
    }

    private var clampedOutlineSidebarWidth: CGFloat {
        min(
            max(
                CGFloat(restorationStore.state.outlineSidebar.width),
                Self.minimumOutlineSidebarWidth
            ),
            Self.maximumOutlineSidebarWidth
        )
    }

    private var outlineColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isOutlineSidebarVisible ? .all : .detailOnly },
            set: { restorationStore.updateOutlineVisibility($0 != .detailOnly) }
        )
    }

    private func presentWorkspaceSearch() {
        selectionActionBarModel.dismiss()
        translationOverlayModel.dismiss()
        appState.refreshNotes()
        appState.refreshVocabulary()
        let notes = appState.notes
        let words = appState.vocabulary
        let document = appState.kitDocument
        let path = appState.selectedDocument?.filePath
        let name = appState.selectedDocument?.fileName
        let markupItems = path.map { FreeMarkupStore.load($0) } ?? []
        let session = inspectorModel.guideSession
        workspaceSearch.present { kind in
            WorkspaceSearchIndex.records(
                for: kind,
                notes: notes,
                words: words,
                document: document,
                pdfPath: path,
                pdfName: name,
                markupItems: markupItems,
                session: session
            )
        }
    }

    private func setReadingInspectorVisible(_ visible: Bool) {
        guard inspectorModel.isVisible != visible else { return }
        guard appState.selectedDocument != nil else {
            withAnimation(.smooth(duration: ReadingWorkspaceView.inspectorTransitionDuration)) {
                inspectorModel.isVisible = visible
            }
            return
        }

        let transitionID = UUID()
        inspectorTransitionID = transitionID
        viewportTransitionController.begin()
        withAnimation(
            .smooth(duration: ReadingWorkspaceView.inspectorTransitionDuration),
            completionCriteria: .logicallyComplete
        ) {
            inspectorModel.isVisible = visible
        } completion: {
            guard inspectorTransitionID == transitionID else { return }
            inspectorTransitionID = nil
            viewportTransitionController.end()
        }
    }

    private func startGuideFromTranslation(_ request: TranslationBubbleRequest) {
        let selection = PDFSelectionContext(
            pdfPath: request.pdfPath,
            pdfName: request.pdfName,
            pageIndex: request.page,
            selectedText: request.word,
            surroundingText: request.sentence,
            bounds: request.bounds,
            boundsStr: request.boundsStr,
            pageMarkups: request.effectivePageMarkups
        )
        translationOverlayModel.dismiss()
        if !inspectorModel.isVisible {
            setReadingInspectorVisible(true)
        }
        inspectorModel.startGuide(selection: selection)
    }

    @discardableResult
    private func saveTranslation(
        result: TranslationResult,
        request: TranslationBubbleRequest
    ) -> String? {
        if request.isSentenceMode {
            return saveSentenceTranslation(result: result, request: request)
        }
        return saveWordTranslation(result: result, request: request)
    }

    private func saveWordTranslation(
        result: TranslationResult,
        request: TranslationBubbleRequest
    ) -> String? {
        guard let entry = try? ReaderPersistence.shared.saveVocabulary(
            word: result.word,
            sentence: request.sentence,
            sentenceHash: request.sentenceHash,
            pdfPath: request.pdfPath,
            pdfName: request.pdfName,
            pageIndex: UInt32(request.page),
            selectionBounds: request.boundsStr,
            phonetic: result.phonetic,
            partOfSpeech: result.partOfSpeech,
            contextTranslation: result.contextTranslation,
            contextExplanation: result.contextExplanation,
            etymology: result.etymology,
            generalDefinition: result.generalDefinition,
            contextSentenceTranslation: result.contextSentenceTranslation,
            translationSource: result.source
        ) else { return nil }

        ReaderEventBus.shared.postAddHighlight(
            entryId: entry.id,
            page: Int(entry.pageIndex),
            boundsStr: request.boundsStr,
            filePath: request.pdfPath
        )
        appState.refreshVocabulary()
        appState.showToast("已保存「\(entry.word)」")
        return entry.id
    }

    private func saveSentenceTranslation(
        result: TranslationResult,
        request: TranslationBubbleRequest
    ) -> String? {
        ReaderPersistence.shared.initializeIfNeeded()
        let noteText = result.contextSentenceTranslation.isEmpty
            ? result.contextTranslation
            : result.contextSentenceTranslation

        guard let note = try? ReaderPersistence.shared.saveNote(
            pdfPath: request.pdfPath,
            pdfName: request.pdfName,
            pageIndex: UInt32(request.page),
            content: request.word,
            note: noteText,
            boundsStr: request.boundsStr,
            pageMarkups: request.effectivePageMarkups
        ) else {
            appState.showToast("保存笔记失败")
            return nil
        }

        ReaderEventBus.shared.postAddUnderlineNote(
            noteId: note.id,
            markups: request.effectivePageMarkups,
            filePath: request.pdfPath,
            undoInfo: NoteUndoInfo(note)
        )
        appState.refreshNotes()
        appState.showToast("已保存到笔记")
        return note.id
    }

    private func deleteTranslationSave(
        id: String,
        savedToNote: Bool,
        request: TranslationBubbleRequest
    ) {
        if savedToNote {
            try? ReaderPersistence.shared.deleteNoteRemovingUnderline(
                id: id,
                filePath: request.pdfPath
            )
            appState.refreshNotes()
            appState.showToast("已从笔记删除")
        } else {
            try? ReaderPersistence.shared.deleteVocabularyRemovingHighlight(
                id: id,
                page: request.page,
                filePath: request.pdfPath
            )
            appState.refreshVocabulary()
            appState.showToast("已从单词本删除")
        }
    }

}

// MARK: - Library Picker Popover

private struct LibraryPickerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已打开的文件")
                    .font(.headline)
                Spacer()
                Button {
                    appState.openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if appState.library.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("还没有打开文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.library, id: \.id) { doc in
                    Button {
                        appState.selectedDocument = doc
                        appState.activeTab = .reader
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            PDFCoverThumbnailView(filePath: doc.filePath)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.fileName)
                                    .font(.callout)
                                    .fontWeight(appState.selectedDocument?.id == doc.id ? .semibold : .regular)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                if doc.totalPages > 0 {
                                    Text("P\(doc.lastPage + 1) / \(doc.totalPages)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if appState.selectedDocument?.id == doc.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            appState.removeFromLibrary(doc)
                        } label: {
                            Label("移除", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("打开一个 PDF 开始阅读")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("选择文件…") {
                appState.openFilePicker()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toast

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
    }
}
