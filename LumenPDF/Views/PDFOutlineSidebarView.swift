import SwiftUI
import PDFKit

struct PDFOutlineSidebarView: View {
    let document: PDFKit.PDFDocument
    @EnvironmentObject private var appState: AppState

    /// The one outline row for the page being read. Several headings can share that page.
    private var activeItemID: ObjectIdentifier? {
        guard let root = document.outlineRoot else { return nil }
        var order = 0
        var items: [(id: ObjectIdentifier, candidate: OutlineSectionCandidate)] = []
        func traverse(_ item: PDFOutline, depth: Int) {
            for index in 0 ..< item.numberOfChildren {
                guard let child = item.child(at: index) else { continue }
                let pageIndex: Int
                if let page = child.destination?.page {
                    let resolved = document.index(for: page)
                    pageIndex = resolved == NSNotFound ? -1 : resolved
                } else {
                    pageIndex = -1
                }
                let pageMaxY = child.destination?.page?.bounds(for: .cropBox).maxY ?? 0
                let destinationY = OutlineDestinationPosition.startY(
                    point: child.destination.map(\.point),
                    pageMaxY: pageMaxY
                )
                items.append((
                    ObjectIdentifier(child),
                    OutlineSectionCandidate(
                        pageIndex: pageIndex,
                        order: order,
                        destinationY: destinationY
                    )
                ))
                order += 1
                traverse(child, depth: depth + 1)
            }
        }
        traverse(root, depth: 0)
        let position = appState.outlineReadingPosition
            ?? OutlineReadingPosition(pageIndex: appState.currentPageIndex, topY: nil)
        guard let activeOrder = OutlineActiveSection.activeOrder(
            in: items.map(\.candidate),
            position: position
        ) else { return nil }
        return items.first { $0.candidate.order == activeOrder }?.id
    }

    var body: some View {
        Group {
            if let root = document.outlineRoot, root.numberOfChildren > 0 {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        // Must be VStack (not LazyVStack): LazyVStack doesn't render
                        // off-screen items, so scrollProxy.scrollTo fails for items
                        // that haven't been laid out yet.
                        VStack(alignment: .leading, spacing: 0) {
                            OutlineChildren(item: root, doc: document,
                                            activeItemID: activeItemID, depth: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        // Delay long enough for the PDFView to finish restoring its
                        // page position (go(to:) is async) before we scroll the TOC.
                        let itemID = activeItemID
                        guard let itemID else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo(itemID, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: activeItemID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(newID, anchor: .center)
                        }
                    }
                    // After window un-minimize, PDFView restores page then fires
                    // pageChanged → currentPageIndex updates → the active section may
                    // not change (same chapter) → onChange won't fire, so we
                    // explicitly re-scroll here.
                    .onReceive(NotificationCenter.default.publisher(for: .windowDidDeminiaturize)) { _ in
                        let itemID = activeItemID
                        guard let itemID else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo(itemID, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("此 PDF 无目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Recursive children

private struct OutlineChildren: View {
    let item: PDFOutline
    let doc: PDFKit.PDFDocument
    let activeItemID: ObjectIdentifier?
    let depth: Int

    var body: some View {
        ForEach(0 ..< item.numberOfChildren, id: \.self) { i in
            if let child = item.child(at: i) {
                OutlineRow(item: child, doc: doc,
                           activeItemID: activeItemID, depth: depth)
            }
        }
    }
}

// MARK: - Single row

private struct OutlineRow: View {
    let item: PDFOutline
    let doc: PDFKit.PDFDocument
    let activeItemID: ObjectIdentifier?
    let depth: Int

    @State private var isExpanded = true

    private var isActive: Bool { ObjectIdentifier(item) == activeItemID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Expand/collapse chevron
                if item.numberOfChildren > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14)
                }

                // Tapping the label navigates
                Button { navigate() } label: {
                    HStack {
                        Text(item.label ?? "")
                            .font(depth == 0 ? .callout.weight(.medium) : .caption)
                            .foregroundStyle(isActive ? Color.accentColor : (depth == 0 ? Color.primary : Color.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .background(
                isActive
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            // ID used by ScrollViewReader to scroll to the single active item.
            .id(ObjectIdentifier(item))

            if item.numberOfChildren > 0 && isExpanded {
                OutlineChildren(item: item, doc: doc,
                                activeItemID: activeItemID, depth: depth + 1)
            }
        }
    }

    private func navigate() {
        guard let page = item.destination?.page else { return }
        let pageIndex = doc.index(for: page)
        guard pageIndex != NSNotFound else { return }
        ReaderEventBus.shared.postOutlineNavigate(
            page: pageIndex,
            filePath: doc.documentURL?.path ?? ""
        )
    }
}
