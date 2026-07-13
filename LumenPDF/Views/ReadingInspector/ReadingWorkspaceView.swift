import SwiftUI

struct ReadingWorkspaceView: View {
    let document: PdfDocument
    @ObservedObject var inspectorModel: ReadingInspectorModel
    @ObservedObject var selectionActionBarModel: SelectionActionBarModel
    let setInspectorVisible: (Bool) -> Void

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var restorationStore = ReadingRestorationStore.shared
    @State private var lastObservedWidth: Double = ReadingInspectorModel.defaultWidth

    var body: some View {
        HSplitView {
            PDFReaderView(
                document: document,
                selectionActionBarModel: selectionActionBarModel,
                onExplainSelection: { selection in
                    if !inspectorModel.isVisible {
                        setInspectorVisible(true)
                    }
                    inspectorModel.startGuide(selection: selection)
                },
                onOpenNotes: {
                    appState.refreshNotes()
                    inspectorModel.mode = .notes
                    if !inspectorModel.isVisible {
                        setInspectorVisible(true)
                    }
                }
            )
            .id(document.id)
            .frame(minWidth: 420)
            .layoutPriority(1)

            if inspectorModel.isVisible {
                ReadingInspectorView(model: inspectorModel) {
                    setInspectorVisible(false)
                }
                .environmentObject(appState)
                .frame(
                    minWidth: restorationStore.isRestoringLayout
                        ? CGFloat(inspectorModel.width)
                        : CGFloat(ReadingInspectorModel.minimumWidth),
                    idealWidth: CGFloat(inspectorModel.width),
                    maxWidth: restorationStore.isRestoringLayout
                        ? CGFloat(inspectorModel.width)
                        : CGFloat(ReadingInspectorModel.maximumWidth)
                )
            }
        }
        .onAppear {
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
            lastObservedWidth = inspectorModel.width
        }
        .onChange(of: document.id) { _, _ in
            selectionActionBarModel.dismiss()
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
        }
        .onChange(of: inspectorModel.width) { oldValue, newValue in
            guard abs(oldValue - newValue) > 1 else { return }
            lastObservedWidth = newValue
            restoreViewportAfterLayoutChange(delay: 0.18)
        }
    }

    private func restoreViewportAfterLayoutChange(delay: TimeInterval) {
        let page = appState.currentPageIndex
        let offset = appState.currentScrollOffset
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            ReaderEventBus.shared.postRestoreReadingViewport(
                filePath: document.filePath,
                page: page,
                scrollOffset: offset
            )
        }
    }
}
