import Foundation
import SwiftUI

@MainActor
final class WorkspaceSearchController: ObservableObject {
    @Published var isPresented = false
    @Published var query = "" {
        didSet { clampSelection() }
    }
    @Published var enabledKinds: Set<WorkspaceSearchKind> = Set(WorkspaceSearchKind.allCases) {
        didSet { clampSelection() }
    }
    @Published var selectedIndex = 0
    @Published private(set) var records: [WorkspaceSearchRecord] = []
    @Published private(set) var focusNonce = 0

    var hits: [WorkspaceSearchHit] {
        WorkspaceSearchMatcher.hits(
            query: query,
            records: records,
            enabledKinds: enabledKinds
        )
    }

    func present(records: [WorkspaceSearchRecord]) {
        self.records = records
        if !isPresented {
            query = ""
            enabledKinds = Set(WorkspaceSearchKind.allCases)
            selectedIndex = 0
            isPresented = true
        }
        focusNonce += 1
        clampSelection()
    }

    func dismiss() {
        isPresented = false
        query = ""
        selectedIndex = 0
        records = []
        enabledKinds = Set(WorkspaceSearchKind.allCases)
    }

    func toggleKind(_ kind: WorkspaceSearchKind) {
        if enabledKinds.contains(kind) {
            guard enabledKinds.count > 1 else { return }
            enabledKinds.remove(kind)
        } else {
            enabledKinds.insert(kind)
        }
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
        let currentHits = hits
        guard currentHits.indices.contains(selectedIndex) else { return currentHits.first }
        return currentHits[selectedIndex]
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
