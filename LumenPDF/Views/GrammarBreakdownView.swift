import SwiftUI

struct GrammarPiece: Identifiable {
    enum Kind {
        case text(String)
        case child(Int)
    }

    let id: Int
    let kind: Kind
}

enum GrammarBreakdownLayout {
    static func pieces(of chunk: SentenceChunk) -> [GrammarPiece] {
        var rest = chunk.original[...]
        var pieces: [GrammarPiece] = []
        var nextID = 0
        for (index, child) in chunk.children.enumerated() {
            guard let range = rest.range(of: child.original) else { continue }
            let prefix = rest[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                pieces.append(GrammarPiece(id: nextID, kind: .text(prefix)))
                nextID += 1
            }
            pieces.append(GrammarPiece(id: nextID, kind: .child(index)))
            nextID += 1
            rest = rest[range.upperBound...]
        }
        let tail = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            pieces.append(GrammarPiece(id: nextID, kind: .text(String(tail))))
        }
        if pieces.isEmpty, !chunk.original.isEmpty {
            pieces.append(GrammarPiece(id: 0, kind: .text(chunk.original)))
        }
        return pieces.filter { piece in
            guard case let .text(text) = piece.kind else { return true }
            return !isConnector(text)
        }
    }

    /// Punctuation and bare coordinators (`and`, `or`, `but`) sit between clauses.
    /// They stay in the source sentence and do not get a row of their own.
    static func isConnector(_ text: String) -> Bool {
        let words = text.split { !$0.isLetter }.map { String($0).lowercased() }.filter { !$0.isEmpty }
        if words.isEmpty { return true }
        return words.allSatisfy { ["and", "or", "but"].contains($0) }
    }

    static func hasNestedStructure(_ chunks: [SentenceChunk]) -> Bool {
        chunks.contains { !$0.children.isEmpty }
    }
}

struct GrammarTreeBlock: View {
    let chunk: SentenceChunk
    let depth: Int

    @State private var isExpanded: Bool

    init(chunk: SentenceChunk, depth: Int) {
        self.chunk = chunk
        self.depth = depth
        _isExpanded = State(initialValue: depth < 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !chunk.children.isEmpty {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isExpanded ? "收起" : "展开")
                }
                if !chunk.role.isEmpty {
                    Text(chunk.role)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.14), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            let pieces = GrammarBreakdownLayout.pieces(of: chunk)
            let leadingCount = pieces.prefix { piece in
                if case .text = piece.kind { return true }
                return false
            }.count
            ForEach(Array(pieces.prefix(leadingCount))) { piece in
                pieceText(piece)
            }
            if !isExpanded, leadingCount == 0, !chunk.original.isEmpty {
                Text(chunk.original)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !chunk.explanation.isEmpty {
                Text(chunk.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded {
                ForEach(Array(pieces.dropFirst(leadingCount))) { piece in
                    switch piece.kind {
                    case let .text(text):
                        Text(text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    case let .child(index):
                        if chunk.children.indices.contains(index) {
                            GrammarTreeBlock(chunk: chunk.children[index], depth: depth + 1)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func toggle() {
        isExpanded.toggle()
    }

    @ViewBuilder
    private func pieceText(_ piece: GrammarPiece) -> some View {
        if case let .text(text) = piece.kind {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
