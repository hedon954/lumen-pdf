import Foundation

extension Notification.Name {
    static let addHighlight           = Notification.Name("addHighlight")
    static let removeHighlight        = Notification.Name("removeHighlight")
    static let addFreeAnnotation      = Notification.Name("addFreeAnnotation")
    static let addUnderlineNote       = Notification.Name("addUnderlineNote")
    static let removeUnderlineNote    = Notification.Name("removeUnderlineNote")
    static let saveReadingPositionNow = Notification.Name("saveReadingPositionNow")
    static let windowDidDeminiaturize = Notification.Name("windowDidDeminiaturize")
    static let refreshNotesList       = Notification.Name("refreshNotesList")
    static let jumpToPage             = Notification.Name("jumpToPage")
    static let jumpToSelectionBounds  = Notification.Name("jumpToSelectionBounds")
    static let restoreReadingViewport = Notification.Name("restoreReadingViewport")
    static let outlineNavigate        = Notification.Name("outlineNavigate")
}

struct ReaderEventBus {
    static let shared = ReaderEventBus()

    var center: NotificationCenter = .default

    func postFreeAnnotation(type: String, boundsStr: String, page: Int, filePath: String) {
        postFreeAnnotations(
            type: type,
            markups: [PDFPageMarkup(pageIndex: page, lineRects: AnnotationBoundsCodec.parse(boundsStr), text: "")],
            filePath: filePath
        )
    }

    func postFreeAnnotations(type: String, markups: [PDFPageMarkup], filePath: String) {
        let bodyMarkups = markups.filter { !$0.lineRects.isEmpty }
        guard !bodyMarkups.isEmpty else { return }
        center.post(
            name: .addFreeAnnotation,
            object: nil,
            userInfo: [
                "annotationType": type,
                "pageIndexes": bodyMarkups.map(\.pageIndex),
                "boundsStrs": bodyMarkups.map(\.boundsStr),
                "pageIndex": bodyMarkups[0].pageIndex,
                "boundsStr": bodyMarkups[0].boundsStr,
                "filePath": filePath
            ]
        )
    }

    func postAddUnderlineNote(noteId: String, page: Int, boundsStr: String, filePath: String, undoInfo: NoteUndoInfo? = nil, deletedNotesInfo: [NoteUndoInfo] = []) {
        var userInfo: [String: Any] = [
            "noteId": noteId,
            "pageIndex": page,
            "boundsStr": boundsStr,
            "filePath": filePath,
            "deletedNoteIds": deletedNotesInfo.map { $0.id },
            "deletedNotesInfo": deletedNotesInfo
        ]
        if let undoInfo {
            userInfo["newNoteInfo"] = undoInfo
        }
        center.post(name: .addUnderlineNote, object: nil, userInfo: userInfo)
    }

    func postRemoveUnderlineNote(noteId: String, page: Int, filePath: String) {
        center.post(
            name: .removeUnderlineNote,
            object: nil,
            userInfo: [
                "noteId": noteId,
                "pageIndex": page,
                "filePath": filePath
            ]
        )
    }

    func postAddHighlight(entryId: String, page: Int, boundsStr: String, filePath: String) {
        center.post(
            name: .addHighlight,
            object: nil,
            userInfo: [
                "entryId": entryId,
                "pageIndex": page,
                "boundsStr": boundsStr,
                "filePath": filePath
            ]
        )
    }

    func postRemoveHighlight(entryId: String, page: Int, filePath: String) {
        center.post(
            name: .removeHighlight,
            object: nil,
            userInfo: [
                "entryId": entryId,
                "pageIndex": page,
                "filePath": filePath
            ]
        )
    }

    func postJumpToPage(page: Int, filePath: String) {
        center.post(
            name: .jumpToPage,
            object: nil,
            userInfo: ["pageIndex": page, "filePath": filePath]
        )
    }

    func postJumpToSelectionBounds(
        page: Int,
        filePath: String,
        boundsStr: String,
        itemId: String? = nil,
        kind: String? = nil
    ) {
        var userInfo = ["pageIndex": page, "filePath": filePath, "boundsStr": boundsStr] as [String: Any]
        if let itemId {
            userInfo["itemId"] = itemId
        }
        if let kind {
            userInfo["kind"] = kind
        }
        center.post(name: .jumpToSelectionBounds, object: nil, userInfo: userInfo)
    }

    func postRestoreReadingViewport(filePath: String, page: Int, scrollOffset: Double) {
        center.post(
            name: .restoreReadingViewport,
            object: nil,
            userInfo: ["filePath": filePath, "pageIndex": page, "scrollOffset": scrollOffset]
        )
    }

    func postSaveReadingPositionNow(filePath: String) {
        center.post(
            name: .saveReadingPositionNow,
            object: nil,
            userInfo: ["filePath": filePath]
        )
    }

    func postOutlineNavigate(page: Int, filePath: String) {
        center.post(
            name: .outlineNavigate,
            object: nil,
            userInfo: ["pageIndex": page, "filePath": filePath]
        )
    }

    func postRefreshNotesList() {
        center.post(name: .refreshNotesList, object: nil)
    }

    func postWindowDidDeminiaturize() {
        center.post(name: .windowDidDeminiaturize, object: nil)
    }
}
