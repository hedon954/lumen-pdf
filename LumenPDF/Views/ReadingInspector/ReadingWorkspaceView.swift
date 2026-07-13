import AppKit
import SwiftUI

struct ReadingWorkspaceView: View {
    let document: PdfDocument
    @ObservedObject var inspectorModel: ReadingInspectorModel
    @ObservedObject var selectionActionBarModel: SelectionActionBarModel
    let setInspectorVisible: (Bool) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var resizeAnchor: ResizeViewportAnchor?

    var body: some View {
        HStack(spacing: 0) {
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
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            if inspectorModel.isVisible {
                ReadingInspectorDivider(
                    inspectorWidth: inspectorModel.width,
                    onResizeBegan: captureResizeAnchor,
                    onResize: { inspectorModel.setWidth(CGFloat($0)) },
                    onResizeEnded: restoreResizeAnchor
                )

                ReadingInspectorView(model: inspectorModel) {
                    setInspectorVisible(false)
                }
                .environmentObject(appState)
                .frame(width: CGFloat(inspectorModel.width))
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
        }
        .onChange(of: document.id) { _, _ in
            selectionActionBarModel.dismiss()
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
        }
    }

    private func captureResizeAnchor() {
        resizeAnchor = ResizeViewportAnchor(
            page: appState.currentPageIndex,
            scrollOffset: appState.currentScrollOffset
        )
    }

    private func restoreResizeAnchor() {
        guard let resizeAnchor else { return }
        self.resizeAnchor = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            ReaderEventBus.shared.postRestoreReadingViewport(
                filePath: document.filePath,
                page: resizeAnchor.page,
                scrollOffset: resizeAnchor.scrollOffset
            )
        }
    }
}

private struct ResizeViewportAnchor {
    let page: Int
    let scrollOffset: Double
}

private struct ReadingInspectorDivider: View {
    let inspectorWidth: Double
    let onResizeBegan: () -> Void
    let onResize: (Double) -> Void
    let onResizeEnded: () -> Void

    @State private var dragStartWidth: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .accessibilityIdentifier("reader.inspectorDivider")
        .help("拖动调整右侧栏宽度")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = inspectorWidth
                        onResizeBegan()
                    }
                    guard let dragStartWidth else { return }
                    onResize(dragStartWidth - Double(value.translation.width))
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    onResizeEnded()
                }
        )
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }
}
