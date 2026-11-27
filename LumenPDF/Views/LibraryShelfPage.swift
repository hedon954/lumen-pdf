import SwiftUI

struct LibraryShelfPage: View {
    @EnvironmentObject private var appState: AppState

    private var showsReturn: Bool {
        appState.selectedDocument != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if appState.shelfPage.children.isEmpty {
                empty
            } else {
                ScrollView {
                    ShelfRail(children: appState.shelfPage.children)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .onAppear { appState.refreshShelf() }
        .accessibilityIdentifier("library.shelf")
    }

    private var header: some View {
        HStack(spacing: 12) {
            if showsReturn {
                Button("返回阅读") { appState.closeLibrary() }
                    .buttonStyle(.borderless)
            }
            crumbs
            Spacer(minLength: 8)
            Button("新建书架") { promptNewShelf() }
                .buttonStyle(.bordered)
            if appState.shelfParentId == nil && !appState.library.isEmpty {
                Button("清空") { appState.confirmClearLibrary() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("library.clear")
            }
            LibraryAddMenu(showsTitle: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var crumbs: some View {
        HStack(spacing: 6) {
            Button("文库") { appState.openShelfCrumb(nil) }
                .buttonStyle(.borderless)
                .fontWeight(appState.shelfParentId == nil ? .semibold : .regular)
            ForEach(appState.shelfPage.crumbs, id: \.id) { shelf in
                Text("/")
                    .foregroundStyle(.tertiary)
                Button(shelf.name) { appState.openShelfCrumb(shelf.id) }
                    .buttonStyle(.borderless)
                    .fontWeight(shelf.id == appState.shelfParentId ? .semibold : .regular)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("这一层还没有书")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promptNewShelf() {
        promptName(title: "新建书架", initial: "") { name in
            appState.createShelf(named: name)
        }
    }
}

private enum ShelfMetrics {
    static let cover = CGSize(width: 168, height: 224)
}

private struct ShelfRail: View {
    let children: [ShelfChild]
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 28, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
            ForEach(children, id: \.shelfItemID) { child in
                ShelfItem(child: child)
            }
        }
    }
}

private struct ShelfItem: View {
    @EnvironmentObject private var appState: AppState
    let child: ShelfChild

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                visual
                Text(title)
                    .font(.callout)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: ShelfMetrics.cover.width, height: 40, alignment: .topLeading)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(isMissing ? .orange : .secondary)
            }
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: dragToken as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            acceptDrop(providers)
        }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var visual: some View {
        switch child {
        case .shelf:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: "books.vertical")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(width: ShelfMetrics.cover.width, height: ShelfMetrics.cover.height)
        case .document(let document):
            PDFCoverThumbnailView(filePath: document.filePath, size: ShelfMetrics.cover)
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .padding(4)
                    }
                }
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
        }
    }

    private var title: String {
        switch child {
        case .shelf(let shelf): return shelf.name
        case .document(let document): return document.fileName
        }
    }

    private var meta: String {
        switch child {
        case .shelf(let shelf):
            return "\(shelf.bookCount) 本"
        case .document(let document):
            if document.isFileMissing { return "找不到文件" }
            if isCurrent { return "正在读 · P\(document.lastPage + 1) / \(document.totalPages)" }
            if document.totalPages > 0 { return "P\(document.lastPage + 1) / \(document.totalPages)" }
            return ""
        }
    }

    private var isMissing: Bool {
        if case .document(let document) = child { return document.isFileMissing }
        return false
    }

    private var isCurrent: Bool {
        if case .document(let document) = child {
            return appState.selectedDocument?.id == document.id
        }
        return false
    }

    private var dragToken: String {
        switch child {
        case .shelf(let shelf): return "shelf \(shelf.id)"
        case .document(let document): return "document \(document.id)"
        }
    }

    private func open() {
        switch child {
        case .shelf(let shelf):
            appState.openShelf(shelf.id)
        case .document(let document):
            appState.selectedDocument = document
            appState.activeTab = .reader
            appState.closeLibrary()
        }
    }

    @ViewBuilder
    private var menu: some View {
        switch child {
        case .shelf(let shelf):
            Button("重命名") { promptRename(shelf) }
            moveMenu(kind: .shelf, id: shelf.id)
            Button("删除", role: .destructive) { appState.confirmDeleteShelf(shelf) }
        case .document(let document):
            moveMenu(kind: .document, id: document.id)
            Button("删除", role: .destructive) { appState.confirmDeleteDocument(document) }
        }
    }

    private func moveMenu(kind: ShelfItemKind, id: String) -> some View {
        Menu("移动到…") {
            Button("文库") { appState.moveShelfItem(kind: kind, id: id, toParent: nil) }
            ForEach(siblingShelves(excluding: id), id: \.id) { shelf in
                Button(shelf.name) {
                    appState.moveShelfItem(kind: kind, id: id, toParent: shelf.id)
                }
            }
        }
    }

    private func siblingShelves(excluding id: String) -> [Shelf] {
        appState.shelfPage.children.compactMap { child in
            if case .shelf(let shelf) = child, shelf.id != id { return shelf }
            return nil
        }
    }

    private func promptRename(_ shelf: Shelf) {
        promptName(title: "重命名书架", initial: shelf.name) { name in
            appState.renameShelf(shelf.id, to: name)
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let token = object as? String else { return }
            let parts = token.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let kind = kind(from: parts[0]) else { return }
            DispatchQueue.main.async {
                handleDrop(kind: kind, id: parts[1])
            }
        }
        return true
    }

    private func handleDrop(kind: ShelfItemKind, id: String) {
        switch child {
        case .shelf(let shelf):
            guard !(kind == .shelf && id == shelf.id) else { return }
            appState.moveShelfItem(kind: kind, id: id, toParent: shelf.id)
        case .document:
            appState.moveBefore(child, draggedKind: kind, draggedId: id)
        }
    }

    private func kind(from token: String) -> ShelfItemKind? {
        switch token {
        case "shelf": return .shelf
        case "document": return .document
        default: return nil
        }
    }
}

private func promptName(title: String, initial: String, confirm: @escaping (String) -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.stringValue = initial
    alert.accessoryView = field
    alert.addButton(withTitle: "好")
    alert.addButton(withTitle: "取消")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    confirm(field.stringValue)
}

extension ShelfChild {
    var shelfItemID: String {
        switch self {
        case .shelf(let shelf): return "shelf-\(shelf.id)"
        case .document(let document): return "document-\(document.id)"
        }
    }
}

extension AppState {
    func moveBefore(_ target: ShelfChild, draggedKind: ShelfItemKind, draggedId: String) {
        var children = shelfPage.children
        guard let from = children.firstIndex(where: { $0.matches(kind: draggedKind, id: draggedId) }),
              let to = children.firstIndex(where: { $0.shelfItemID == target.shelfItemID }),
              from != to
        else { return }
        let item = children.remove(at: from)
        let destination = children.firstIndex(where: { $0.shelfItemID == target.shelfItemID }) ?? children.endIndex
        children.insert(item, at: min(destination, children.count))
        reorderShelf(to: children)
    }
}

extension ShelfChild {
    func matches(kind: ShelfItemKind, id: String) -> Bool {
        switch (self, kind) {
        case (.shelf(let shelf), .shelf): return shelf.id == id
        case (.document(let document), .document): return document.id == id
        default: return false
        }
    }
}
