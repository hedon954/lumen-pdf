import AppKit
import SwiftUI

struct ReadingWorkspaceView: View {
    static let inspectorTransitionDuration: TimeInterval = 0.22

    let document: PdfDocument
    @ObservedObject var inspectorModel: ReadingInspectorModel
    @ObservedObject var selectionActionBarModel: SelectionActionBarModel
    @ObservedObject var viewportTransitionController: ReaderViewportTransitionController
    let setInspectorVisible: (Bool) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var isInspectorContentMounted = true
    @State private var inspectorContentGeneration = UUID()

    var body: some View {
        HStack(spacing: 0) {
            PDFReaderView(
                document: document,
                selectionActionBarModel: selectionActionBarModel,
                viewportTransitionController: viewportTransitionController,
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

            HStack(spacing: 0) {
                if isInspectorContentMounted {
                    ReadingInspectorDivider(
                        inspectorWidth: inspectorModel.width,
                        onResizeBegan: beginResizeTransition,
                        onResize: { inspectorModel.setWidth(CGFloat($0)) },
                        onResizeEnded: endResizeTransition
                    )

                    ReadingInspectorView(model: inspectorModel) {
                        setInspectorVisible(false)
                    }
                    .environmentObject(appState)
                    .frame(width: CGFloat(inspectorModel.width))
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(width: inspectorChromeWidth, alignment: .leading)
            .clipped()
            .opacity(inspectorModel.isVisible ? 1 : 0)
            .allowsHitTesting(inspectorModel.isVisible)
            .accessibilityHidden(!inspectorModel.isVisible)
            .animation(
                .smooth(duration: Self.inspectorTransitionDuration),
                value: inspectorModel.isVisible
            )
        }
        .onAppear {
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
            isInspectorContentMounted = inspectorModel.isVisible
        }
        .onChange(of: document.id) { _, _ in
            selectionActionBarModel.dismiss()
            inspectorModel.clearForDocumentChange(pdfPath: document.filePath)
        }
        .onChange(of: inspectorModel.isVisible) { _, isVisible in
            updateInspectorContentMount(isVisible: isVisible)
        }
    }

    private var inspectorChromeWidth: CGFloat {
        inspectorModel.isVisible ? CGFloat(inspectorModel.width) + 8 : 0
    }

    private func beginResizeTransition() {
        viewportTransitionController.begin()
    }

    private func endResizeTransition() {
        DispatchQueue.main.async {
            viewportTransitionController.end()
        }
    }

    private func updateInspectorContentMount(isVisible: Bool) {
        let generation = UUID()
        inspectorContentGeneration = generation
        if isVisible {
            isInspectorContentMounted = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.inspectorTransitionDuration) {
            guard inspectorContentGeneration == generation,
                  !inspectorModel.isVisible else { return }
            isInspectorContentMounted = false
        }
    }
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
