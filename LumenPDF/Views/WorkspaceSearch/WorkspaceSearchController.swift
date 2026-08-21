import Foundation
import SwiftUI

@MainActor
final class WorkspaceSearchController: ObservableObject {
    @Published var isPresented = false
    @Published var query = "" {
        didSet { scheduleHitRefresh() }
    }
    @Published var enabledKinds: Set<WorkspaceSearchKind> = WorkspaceSearchKind.defaultEnabled
    @Published var selectedIndex = 0
    @Published private(set) var hits: [WorkspaceSearchHit] = []
    @Published private(set) var focusNonce = 0

    private var recordsByKind: [WorkspaceSearchKind: [WorkspaceSearchRecord]] = [:]
    private var loadKind: ((WorkspaceSearchKind) -> [WorkspaceSearchRecord])?
    private var hitRefreshTask: Task<Void, Never>?

    var activeRecords: [WorkspaceSearchRecord] {
        WorkspaceSearchKind.allCases.flatMap { kind in
            guard enabledKinds.contains(kind) else { return [] }
            return recordsByKind[kind] ?? []
        }
    }

    func present(loader: @escaping (WorkspaceSearchKind) -> [WorkspaceSearchRecord]) {
        loadKind = loader
        if !isPresented {
            query = ""
            enabledKinds = WorkspaceSearchKind.defaultEnabled
            selectedIndex = 0
            recordsByKind = [:]
            isPresented = true
        }
        for kind in enabledKinds {
            recordsByKind[kind] = loader(kind)
        }
        focusNonce += 1
        refreshHitsImmediately()
    }

    func dismiss() {
        hitRefreshTask?.cancel()
        isPresented = false
        selectedIndex = 0
        hits = []
        recordsByKind = [:]
        loadKind = nil
        enabledKinds = WorkspaceSearchKind.defaultEnabled
        if !query.isEmpty {
            query = ""
        }
        hitRefreshTask?.cancel()
    }

    func toggleKind(_ kind: WorkspaceSearchKind) {
        if enabledKinds.contains(kind) {
            guard enabledKinds.count > 1 else { return }
            enabledKinds.remove(kind)
        } else {
            enabledKinds.insert(kind)
            if recordsByKind[kind] == nil {
                recordsByKind[kind] = loadKind?(kind) ?? []
            }
        }
        refreshHitsImmediately()
    }

    func moveSelection(_ delta: Int) {
        let count = hits.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func selectedHit() -> WorkspaceSearchHit? {
        guard hits.indices.contains(selectedIndex) else { return hits.first }
        return hits[selectedIndex]
    }

    private func scheduleHitRefresh() {
        hitRefreshTask?.cancel()
        hitRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            refreshHitsImmediately()
        }
    }

    private func refreshHitsImmediately() {
        hitRefreshTask?.cancel()
        hits = WorkspaceSearchMatcher.hits(
            query: query,
            records: activeRecords,
            enabledKinds: enabledKinds
        )
        clampSelection()
    }

    private func clampSelection() {
        let count = hits.count
        if count == 0 {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(selectedIndex, 0), count - 1)
        }
    }
}

enum WorkspaceSearchOpener {
    @MainActor
    static func open(
        _ hit: WorkspaceSearchHit,
        query: String,
        appState: AppState,
        inspectorModel: ReadingInspectorModel,
        setInspectorVisible: (Bool) -> Void
    ) {
        let record = hit.record
        appState.activeTab = .reader

        let needsDocumentSwitch = !record.pdfPath.isEmpty
            && appState.selectedDocument?.filePath != record.pdfPath
        if needsDocumentSwitch {
            guard let doc = appState.library.first(where: { $0.filePath == record.pdfPath }) else {
                appState.showToast("找不到对应的 PDF")
                return
            }
            appState.selectedDocument = doc
        }

        if let mode = record.kind.inspectorMode {
            inspectorModel.mode = mode
            if appState.selectedDocument != nil {
                setInspectorVisible(true)
            }
        }

        let delay: TimeInterval = needsDocumentSwitch ? 0.35 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !record.boundsStr.isEmpty {
                ReaderEventBus.shared.postJumpToSelectionBounds(
                    page: record.pageIndex,
                    filePath: record.pdfPath,
                    boundsStr: record.boundsStr,
                    itemId: record.id,
                    kind: record.kind.rawValue
                )
            } else if !record.pdfPath.isEmpty {
                ReaderEventBus.shared.postJumpToPage(
                    page: record.pageIndex,
                    filePath: record.pdfPath
                )
            }

            if record.kind == .original, !record.pdfPath.isEmpty {
                let tokens = WorkspaceSearchMatcher.tokens(in: query)
                let needle = tokens.joined(separator: " ")
                if !needle.isEmpty {
                    ReaderEventBus.shared.postHighlightSearchQuery(
                        query: needle,
                        page: record.pageIndex,
                        filePath: record.pdfPath
                    )
                }
            }
        }
    }
}
