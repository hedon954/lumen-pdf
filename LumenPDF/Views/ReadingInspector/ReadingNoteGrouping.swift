import Foundation

struct ReadingInspectorNoteItem: Identifiable, Equatable {
    let id: String
    let noteId: String
    let itemIndex: Int
    let markdown: String
    let createdAt: Int64
}

struct ReadingInspectorNoteGroup: Identifiable, Equatable {
    let id: String
    let sourceId: String
    let sourceIds: [String]
    let pdfPath: String
    let pageIndex: UInt32
    let boundsStr: String
    let title: String
    let notes: [ReadingInspectorNoteItem]
    let createdAt: Int64

    static func groups(from notes: [NoteEntry]) -> [ReadingInspectorNoteGroup] {
        let grouped = Dictionary(grouping: notes, by: NoteSelectionKey.init)
        return grouped.values.compactMap { entries in
            let sortedEntries = entries.enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.createdAt != rhs.element.createdAt {
                        return lhs.element.createdAt > rhs.element.createdAt
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            guard let representative = sortedEntries.first else { return nil }
            let noteItems = sortedEntries.flatMap { note in
                let decoded = NoteTextList.decode(note.note)
                return decoded.enumerated().map { index, item in
                    ReadingInspectorNoteItem(
                        id: decoded.count == 1 ? note.id : "\(note.id)#\(index)",
                        noteId: note.id,
                        itemIndex: index,
                        markdown: item,
                        createdAt: note.createdAt
                    )
                }
            }
            guard !noteItems.isEmpty else { return nil }
            return ReadingInspectorNoteGroup(
                id: NoteSelectionKey(representative).stableId,
                sourceId: representative.id,
                sourceIds: sortedEntries.map(\.id),
                pdfPath: representative.pdfPath,
                pageIndex: representative.pageIndex,
                boundsStr: representative.boundsStr,
                title: ContextSentenceFormatting.displayParagraph(representative.content),
                notes: noteItems,
                createdAt: representative.createdAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
    }
}

private struct NoteSelectionKey: Hashable {
    let pdfPath: String
    let pageIndex: UInt32
    let boundsStr: String
    let content: String

    init(_ note: NoteEntry) {
        pdfPath = note.pdfPath
        pageIndex = note.pageIndex
        boundsStr = note.boundsStr
        content = ContextSentenceFormatting.displayParagraph(note.content)
    }

    var stableId: String {
        "note|\(pdfPath)|\(pageIndex)|\(boundsStr)|\(content)"
    }
}

enum ReadingInspectorDateFormat {
    static func timestampText(for createdAt: Int64) -> String? {
        guard createdAt > 0 else { return nil }
        let rawSeconds = Double(createdAt)
        let seconds = createdAt > 10_000_000_000 ? rawSeconds / 1_000 : rawSeconds
        let date = Date(timeIntervalSince1970: seconds)
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return monthDayTimeFormatter.string(from: date)
        }
        return dateTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()
}
