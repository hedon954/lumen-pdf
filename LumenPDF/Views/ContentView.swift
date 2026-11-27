import SwiftUI
import PDFKit
import AppKit

private enum WorkspaceTab: Hashable {
    case library, reader, vocabulary, notes
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSetupSheet = false
    @State private var inspectorTransitionID: UUID?
    @StateObject private var inspectorModel = ReadingInspectorModel()
    @StateObject private var selectionActionBarModel = SelectionActionBarModel()
    @StateObject private var readingPopoverModel = ReadingPopoverModel()
    @StateObject private var viewportTransitionController = ReaderViewportTransitionController()
    @StateObject private var workspaceSearch = WorkspaceSearchController()
    @ObservedObject private var restorationStore = ReadingRestorationStore.shared
    @EnvironmentObject private var appUpdate: AppUpdateCenter
    @Environment(\.openWindow) private var openWindow
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
                    guard isOutlineSidebarVisible, !appState.showsLibraryShelf else { return }
                    restorationStore.updateOutlineWidth(Double(width))
                }
            }
        } detail: {
            ZStack(alignment: .bottom) {
                // Keep PDFReaderView alive (never destroyed on tab switch),
                // so scroll position is preserved.
                let showShelf = appState.showsLibraryShelf
                if let doc = appState.selectedDocument {
                    ReadingWorkspaceView(
                        document: doc,
                        inspectorModel: inspectorModel,
                        selectionActionBarModel: selectionActionBarModel,
                        readingPopoverModel: readingPopoverModel,
                        viewportTransitionController: viewportTransitionController,
                        setInspectorVisible: setReadingInspectorVisible
                    )
                    .opacity(appState.activeTab == .reader && !showShelf ? 1 : 0)
                    .allowsHitTesting(appState.activeTab == .reader && !showShelf)
                }

                if showShelf {
                    LibraryShelfPage()
                }

                if appState.activeTab == .vocabulary && !showShelf {
                    VocabularyListView()
                }

                if appState.activeTab == .notes && !showShelf {
                    NoteListView()
                }

                if let toast = appState.toast {
                    ToastView(message: toast.message, onUndo: toast.undo)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: toast.id)
                }
            }
        }
        .coordinateSpace(name: ReaderRootCoordinateSpace.name)
        .overlay {
            if appState.activeTab == .reader && !appState.showsLibraryShelf {
                SelectionActionBarOverlay(model: selectionActionBarModel)
            }
        }
        .overlay {
            if appState.activeTab == .reader && !appState.showsLibraryShelf,
               let presentation = readingPopoverModel.presentation
            {
                GeometryReader { proxy in
                    let anchor = TranslationPopoverGeometry.selectionFrame(
                        ReaderRootCoordinateSpace.localRect(
                            presentation.anchorRect,
                            overlayFrameInRoot: proxy.frame(
                                in: .named(ReaderRootCoordinateSpace.name)
                            )
                        )
                    )
                    ReadingOverlayPanelHost(
                        resetID: readingPopoverModel.generation,
                        anchorRect: anchor,
                        availableSize: proxy.size,
                        placementOrder: overlayPlacementOrder(for: presentation),
                        preferredGap: overlayPreferredGap(for: presentation),
                        compactVerticalInset: overlayCompactInset(for: presentation)
                    ) {
                        switch presentation {
                        case let .translation(request):
                            TranslationBubble(
                                request: request,
                                isLoading: readingPopoverModel.isLoading,
                                availableSize: proxy.size,
                                overlayAnchorRect: anchor,
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
                                onToggleHighlight: {
                                    toggleTranslationHighlight(request)
                                },
                                onRetry: readingPopoverModel.retry,
                                onDismiss: readingPopoverModel.dismiss
                            )
                        case let .noteDraft(draft, save):
                            UnderlineNoteDraftView(
                                draft: draft, availableSize: proxy.size, overlayAnchorRect: anchor,
                                onCancel: readingPopoverModel.dismiss, onSave: save
                            )
                        case let .noteReview(review, actions):
                            NoteReviewPopoverView(
                                review: review, availableSize: proxy.size, overlayAnchorRect: anchor,
                                onOpenNotes: actions.openNotes, onSaveItem: actions.saveItem,
                                onAppend: actions.append, onDeleteItem: actions.deleteItem,
                                onDeleteAll: actions.deleteAll, onClose: readingPopoverModel.dismiss
                            )
                        }
                    }

                }
                .allowsHitTesting(false)
                .id(readingPopoverModel.generation)
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
            ToolbarItem(placement: .principal) {
                HStack(alignment: .center, spacing: 8) {
                    Picker("", selection: workspaceTab) {
                        Text("文库").tag(WorkspaceTab.library)
                        Text("阅读").tag(WorkspaceTab.reader)
                        Text("单词").tag(WorkspaceTab.vocabulary)
                        Text("笔记").tag(WorkspaceTab.notes)
                    }
                    .accessibilityIdentifier("toolbar.mainTabs")
                    .pickerStyle(.segmented)
                    .fixedSize()

                    readerLocationLabel
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

                if appState.activeTab == .reader
                    && !appState.showsLibraryShelf
                    && appState.selectedDocument != nil {
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

                LibraryAddMenu(showsTitle: true)
                    .accessibilityIdentifier("toolbar.openPDF")

                Button {
                    openWindow(id: AppSceneID.settings)
                } label: {
                    Label("设置", systemImage: "gear")
                }
                .accessibilityIdentifier("toolbar.settings")
            }
        }
        .overlay(alignment: .top) {
            if !workspaceSearch.isPresented {
                AppUpdateBanner(updates: appUpdate)
            }
        }
        .sheet(isPresented: $appUpdate.showsSheet) {
            AppUpdateSheet(updates: appUpdate)
        }
        .task {
            appUpdate.startIfNeeded()
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
                .environmentObject(appUpdate)
                .frame(idealWidth: 940, minHeight: 600, idealHeight: 680)
        }
        .onChange(of: appState.activeTab) { _, _ in
            selectionActionBarModel.dismiss()
            readingPopoverModel.dismiss()
        }
        .onChange(of: appState.selectedDocument?.id) { _, _ in
            selectionActionBarModel.dismiss()
            readingPopoverModel.dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentWorkspaceSearch)) { _ in
            presentWorkspaceSearch()
        }
        .onDisappear { readingPopoverModel.dismiss() }
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
            get: {
                if appState.showsLibraryShelf || !isOutlineSidebarVisible {
                    return .detailOnly
                }
                return .all
            },
            set: { newValue in
                guard !appState.showsLibraryShelf else { return }
                restorationStore.updateOutlineVisibility(newValue != .detailOnly)
            }
        )
    }

    private var workspaceTab: Binding<WorkspaceTab> {
        Binding(
            get: {
                if appState.showsLibraryShelf { return .library }
                switch appState.activeTab {
                case .reader: return .reader
                case .vocabulary: return .vocabulary
                case .notes: return .notes
                }
            },
            set: { tab in
                switch tab {
                case .library: appState.openLibrary()
                case .reader: appState.showReading()
                case .vocabulary: appState.showSection(.vocabulary)
                case .notes: appState.showSection(.notes)
                }
            }
        )
    }

    @ViewBuilder
    private var readerLocationLabel: some View {
        if let fileName = appState.selectedDocument?.fileName, !appState.showsLibraryShelf {
            Divider().frame(height: 12)
            HStack(spacing: 6) {
                Text(fileName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if appState.activeTab == .reader, appState.totalPages > 0 {
                    Text("\(appState.currentPageIndex + 1) / \(appState.totalPages)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .animation(.none, value: appState.currentPageIndex)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
        }
    }

    private func presentWorkspaceSearch() {
        selectionActionBarModel.dismiss()
        readingPopoverModel.dismiss()
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

    private func overlayPlacementOrder(
        for presentation: ReadingPopoverModel.Presentation
    ) -> [ReadingOverlayPlacement] {
        switch presentation {
        case .translation:
            return ReadingOverlayPlacement.lookUpOrder
        case .noteDraft, .noteReview:
            return ReadingOverlayPlacement.defaultOrder
        }
    }

    private func overlayPreferredGap(
        for presentation: ReadingPopoverModel.Presentation
    ) -> CGFloat {
        switch presentation {
        case .translation: return 2
        case .noteDraft, .noteReview: return 12
        }
    }

    private func overlayCompactInset(
        for presentation: ReadingPopoverModel.Presentation
    ) -> Bool {
        switch presentation {
        case .translation: return true
        case .noteDraft, .noteReview: return false
        }
    }

    private func toggleTranslationHighlight(_ request: TranslationBubbleRequest) {
        ReaderEventBus.shared.postFreeAnnotations(
            type: "highlight",
            markups: request.effectivePageMarkups,
            filePath: request.pdfPath
        )
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
        readingPopoverModel.dismiss()
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

// MARK: - Library add menu

struct LibraryAddMenu: View {
    @EnvironmentObject private var appState: AppState
    var showsTitle: Bool

    var body: some View {
        Menu {
            Button("打开 PDF…") {
                appState.openFilePicker()
            }
            .accessibilityIdentifier(showsTitle ? "toolbar.openPDF.file" : "library.openPDF")
            Button("导入文件夹…") {
                appState.openFolderPicker()
            }
            .accessibilityIdentifier(showsTitle ? "toolbar.importFolder" : "library.importFolder")
        } label: {
            if showsTitle {
                Label("打开 PDF", systemImage: "plus")
            } else {
                Image(systemName: "plus")
            }
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("打开 PDF 或导入文件夹")
    }
}

// MARK: - Toast

private struct ToastView: View {
    let message: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.callout)
            if let onUndo {
                Divider().frame(height: 14)
                Button("撤回", action: onUndo)
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
                    .accessibilityIdentifier("toast.undo")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}
