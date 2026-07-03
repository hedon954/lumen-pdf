import SwiftUI

struct ReadingWorkspaceView: View {
    let document: PdfDocument
    @ObservedObject var inspectorModel: ReadingInspectorModel
    let setInspectorVisible: (Bool) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var lastObservedWidth: Double = ReadingInspectorModel.defaultWidth

    var body: some View {
        HSplitView {
            PDFReaderView(document: document) { selection in
                if !inspectorModel.isVisible {
                    setInspectorVisible(true)
                }
                inspectorModel.startGuide(selection: selection)
            }
            .id(document.id)
            .frame(minWidth: 420)

            if inspectorModel.isVisible {
                ReadingInspectorView(model: inspectorModel) {
                    setInspectorVisible(false)
                }
                .environmentObject(appState)
                .frame(
                    minWidth: CGFloat(ReadingInspectorModel.minimumWidth),
                    idealWidth: CGFloat(inspectorModel.width),
                    maxWidth: CGFloat(ReadingInspectorModel.maximumWidth)
                )
            }
        }
        .onAppear {
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
            lastObservedWidth = inspectorModel.width
        }
        .onChange(of: document.id) { _, _ in
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
            NotificationCenter.default.post(
                name: .restoreReadingViewport,
                object: nil,
                userInfo: [
                    "filePath": document.filePath,
                    "pageIndex": page,
                    "scrollOffset": offset
                ]
            )
        }
    }
}
