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
    static let presentWorkspaceSearch = Notification.Name("presentWorkspaceSearch")
    static let highlightSearchQuery   = Notification.Name("highlightSearchQuery")
}

struct ReaderEventBus {
    static let shared = ReaderEventBus()

    var center: NotificationCenter = .default

    func postFreeAnnotations(type: String, markups: [PDFPageMarkup], filePath: String) {
        guard var userInfo = pageMarkupUserInfo(markups) else { return }
        userInfo["annotationType"] = type
        userInfo["filePath"] = filePath
        center.post(
            name: .addFreeAnnotation,
            object: nil,
            userInfo: userInfo
        )
    }

    func postAddUnderlineNote(
        noteId: String,
        markups: [PDFPageMarkup],
        filePath: String,
        undoInfo: NoteUndoInfo? = nil,
        deletedNotesInfo: [NoteUndoInfo] = []
    ) {
        guard var userInfo = pageMarkupUserInfo(markups) else { return }
        userInfo["noteId"] = noteId
        userInfo["filePath"] = filePath
        userInfo["deletedNoteIds"] = deletedNotesInfo.map { $0.id }
        userInfo["deletedNotesInfo"] = deletedNotesInfo
        if let undoInfo {
            userInfo["newNoteInfo"] = undoInfo
        }
        center.post(name: .addUnderlineNote, object: nil, userInfo: userInfo)
    }

    private func pageMarkupUserInfo(_ markups: [PDFPageMarkup]) -> [String: Any]? {
        let bodyMarkups = PDFPageMarkupCodec.normalized(markups)
        guard let first = bodyMarkups.first else { return nil }
        return [
            "pageIndexes": bodyMarkups.map(\.pageIndex),
            "boundsStrs": bodyMarkups.map(\.boundsStr),
            "pageIndex": first.pageIndex,
            "boundsStr": first.boundsStr,
        ]
    }

    func postRemoveUnderlineNote(
        noteId: String,
        filePath: String,
        undoInfo: NoteUndoInfo? = nil
    ) {
        var userInfo: [String: Any] = [
            "noteId": noteId,
            "filePath": filePath,
        ]
        if let undoInfo {
            userInfo["deletedNoteInfo"] = undoInfo
        }
        center.post(
            name: .removeUnderlineNote,
            object: nil,
            userInfo: userInfo
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
        markups: [PDFPageMarkup] = [],
        itemId: String? = nil,
        kind: String? = nil
    ) {
        var userInfo = ["pageIndex": page, "filePath": filePath, "boundsStr": boundsStr] as [String: Any]
        if let markupUserInfo = pageMarkupUserInfo(markups) {
            userInfo.merge(markupUserInfo) { _, markupValue in markupValue }
        }
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

    func postPresentWorkspaceSearch() {
        center.post(name: .presentWorkspaceSearch, object: nil)
    }

    func postHighlightSearchQuery(query: String, page: Int, filePath: String) {
        center.post(
            name: .highlightSearchQuery,
            object: nil,
            userInfo: ["query": query, "pageIndex": page, "filePath": filePath]
        )
    }
}
