import SwiftUI
import PDFKit
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLibrary = false
    @State private var showSetupSheet = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var inspectorModel = ReadingInspectorModel()
    @AppStorage("llm_base_url") private var baseURL = ""
    @AppStorage("llm_model") private var model = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
            .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            ZStack(alignment: .bottom) {
                // Keep PDFReaderView alive (never destroyed on tab switch),
                // so scroll position is preserved.
                if let doc = appState.selectedDocument {
                    ReadingWorkspaceView(
                        document: doc,
                        inspectorModel: inspectorModel,
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
                        .frame(width: 280, height: 360)
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
            let storedKey = KeychainService.load(key: "llm_api_key") ?? ""
            if baseURL.isEmpty || storedKey.isEmpty || model.isEmpty {
                showSetupSheet = true
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            SettingsView(onDismiss: { showSetupSheet = false })
                .environmentObject(appState)
        }
    }
    private func setReadingInspectorVisible(_ visible: Bool) {
        guard inspectorModel.isVisible != visible else { return }
        guard let doc = appState.selectedDocument else {
            inspectorModel.isVisible = visible
            return
        }
        ReaderEventBus.shared.postSaveReadingPositionNow(filePath: doc.filePath)
        DispatchQueue.main.async {
            let page = appState.currentPageIndex
            let offset = appState.currentScrollOffset
            inspectorModel.isVisible = visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                ReaderEventBus.shared.postRestoreReadingViewport(
                    filePath: doc.filePath,
                    page: page,
                    scrollOffset: offset
                )
            }
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
                        HStack {
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
                            Spacer()
                            if appState.selectedDocument?.id == doc.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                        }
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
