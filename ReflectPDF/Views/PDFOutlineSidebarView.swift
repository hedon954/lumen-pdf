import SwiftUI
import PDFKit

/// Shows the PDF's built-in table of contents (outline).
/// Tapping an item scrolls the associated PDFReaderView to that destination.
struct PDFOutlineSidebarView: View {
    let document: PDFKit.PDFDocument

    var body: some View {
        Group {
            if let root = document.outlineRoot, root.numberOfChildren > 0 {
                List {
                    OutlineChildren(item: root, depth: 0)
                }
                .listStyle(.sidebar)
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
        .navigationTitle("目录")
    }
}

// MARK: - Recursive outline renderer

private struct OutlineChildren: View {
    let item: PDFOutline
    let depth: Int

    var body: some View {
        ForEach(0 ..< item.numberOfChildren, id: \.self) { i in
            if let child = item.child(at: i) {
                OutlineRow(item: child, depth: depth)
            }
        }
    }
}

private struct OutlineRow: View {
    let item: PDFOutline
    let depth: Int

    @State private var isExpanded = true

    var body: some View {
        if item.numberOfChildren > 0 {
            DisclosureGroup(isExpanded: $isExpanded) {
                OutlineChildren(item: item, depth: depth + 1)
            } label: {
                label
            }
        } else {
            label
                .contentShape(Rectangle())
                .onTapGesture { navigate() }
        }
    }

    private var label: some View {
        HStack {
            Text(item.label ?? "")
                .font(depth == 0 ? .callout.weight(.medium) : .caption)
                .foregroundStyle(depth == 0 ? .primary : .secondary)
                .lineLimit(2)
                .padding(.leading, CGFloat(depth) * 8)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { navigate() }
    }

    private func navigate() {
        guard let dest = item.destination,
              let page = dest.page,
              let doc = page.document else { return }

        // Post a notification that PDFReaderView's PDFView can observe
        NotificationCenter.default.post(
            name: .outlineNavigate,
            object: nil,
            userInfo: ["destination": dest, "document": doc]
        )
    }
}

extension Notification.Name {
    static let outlineNavigate = Notification.Name("outlineNavigate")
}
