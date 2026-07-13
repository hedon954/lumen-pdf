import AppKit
import SwiftUI

/// A narrow AppKit bridge that reads and restores the real pane owned by the
/// nearest native split view. SwiftUI geometry preferences can emit only during
/// the initial locked layout, so guarding that first value may otherwise leave
/// no later change to persist.
struct SplitPaneWidthObserver: NSViewRepresentable {
    enum Edge {
        case leading
        case trailing
    }

    let edge: Edge
    let restoredWidth: CGFloat
    let isRestoring: Bool
    let onStableWidthChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ObservationView {
        ObservationView()
    }

    func updateNSView(_ nsView: ObservationView, context: Context) {
        nsView.configure(
            edge: edge,
            restoredWidth: restoredWidth,
            isRestoring: isRestoring,
            onStableWidthChange: onStableWidthChange
        )
    }

    final class ObservationView: NSView {
        private var edge: Edge = .leading
        private var restoredWidth: CGFloat = 0
        private var isRestoring = true
        private var onStableWidthChange: ((CGFloat) -> Void)?
        private var synchronizationWorkItem: DispatchWorkItem?
        private var isApplyingRestoredWidth = false
        private var hasAppliedCurrentRestoration = false
        private var lastReportedWidth: CGFloat = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleSynchronization()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleSynchronization()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            scheduleSynchronization()
        }

        override func layout() {
            super.layout()
            scheduleSynchronization()
        }

        func configure(
            edge: Edge,
            restoredWidth: CGFloat,
            isRestoring: Bool,
            onStableWidthChange: @escaping (CGFloat) -> Void
        ) {
            if self.isRestoring != isRestoring
                || abs(self.restoredWidth - restoredWidth) > 0.5 {
                hasAppliedCurrentRestoration = false
            }
            self.edge = edge
            self.restoredWidth = restoredWidth
            self.isRestoring = isRestoring
            self.onStableWidthChange = onStableWidthChange
            scheduleSynchronization()
        }

        private func scheduleSynchronization() {
            synchronizationWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.synchronizeWidth()
            }
            synchronizationWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        private func synchronizeWidth() {
            guard !isApplyingRestoredWidth else { return }

            if isRestoring {
                applyRestoredWidth()
            } else {
                reportStableWidth()
            }
        }

        private func applyRestoredWidth() {
            guard restoredWidth > 0,
                  let context = splitPaneContext(),
                  (!hasAppliedCurrentRestoration
                      || abs(context.pane.frame.width - restoredWidth) > 0.5),
                  context.splitView.bounds.width > restoredWidth
            else { return }

            isApplyingRestoredWidth = true
            switch edge {
            case .leading:
                context.splitView.setPosition(restoredWidth, ofDividerAt: context.dividerIndex)
            case .trailing:
                let position = context.splitView.bounds.width
                    - restoredWidth
                    - context.splitView.dividerThickness
                context.splitView.setPosition(position, ofDividerAt: context.dividerIndex)
            }
            isApplyingRestoredWidth = false
            hasAppliedCurrentRestoration = true
        }

        private func reportStableWidth() {
            guard let window,
                  window.isVisible,
                  !window.isMiniaturized,
                  let width = splitPaneContext()?.pane.frame.width ?? positiveBoundsWidth,
                  abs(width - lastReportedWidth) > 0.5
            else { return }

            lastReportedWidth = width
            onStableWidthChange?(width)
        }

        private var positiveBoundsWidth: CGFloat? {
            bounds.width > 0 ? bounds.width : nil
        }

        private struct SplitPaneContext {
            let splitView: NSSplitView
            let pane: NSView
            let dividerIndex: Int
        }

        private func splitPaneContext() -> SplitPaneContext? {
            var descendant: NSView = self
            var ancestor = superview

            while let current = ancestor {
                if let splitView = current as? NSSplitView,
                   let paneIndex = splitView.arrangedSubviews.firstIndex(of: descendant),
                   splitView.arrangedSubviews.count >= 2 {
                    let lastIndex = splitView.arrangedSubviews.count - 1
                    switch edge {
                    case .leading where paneIndex == 0:
                        return SplitPaneContext(
                            splitView: splitView,
                            pane: descendant,
                            dividerIndex: 0
                        )
                    case .trailing where paneIndex == lastIndex:
                        return SplitPaneContext(
                            splitView: splitView,
                            pane: descendant,
                            dividerIndex: lastIndex - 1
                        )
                    default:
                        break
                    }
                }
                descendant = current
                ancestor = current.superview
            }
            return nil
        }

        deinit {
            synchronizationWorkItem?.cancel()
        }
    }
}
