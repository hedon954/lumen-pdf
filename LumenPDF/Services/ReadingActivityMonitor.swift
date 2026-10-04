import AppKit
import PDFKit

/// 把阅读窗口的状态上报给 Rust 的阅读计时器（写 `activity.jsonl` 的 `read` 行）。
/// 只上报文档 id、路径、文件名和页码，从不上报 PDF 正文。是否计时、何时落盘都由 Rust 决定。
@MainActor
final class ReadingActivityMonitor {
    /// 主阅读窗口的 autosave 名，见 `WindowFramePersistence`。
    static let mainWindowAutosaveName = "LumenPDFMainWindow"
    /// 输入最多每隔这么久上报一次；计时器按 2 分钟判断空闲，几秒的误差无关紧要。
    static let inputThrottle: TimeInterval = 5
    static let tickInterval: TimeInterval = 15

    private let report: (ReadingEvent) -> Void
    private let isReaderTabActive: () -> Bool
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var timer: Timer?
    private var lastInputReport = Date.distantPast
    private var lastFront: Bool?
    private var openDocumentID: String?

    init(report: @escaping (ReadingEvent) -> Void, isReaderTabActive: @escaping () -> Bool) {
        self.report = report
        self.isReaderTabActive = isReaderTabActive
    }

    func start() {
        guard timer == nil else { return }
        let center = NotificationCenter.default
        let frontChanges: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification
        ]
        for name in frontChanges {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFront() }
            })
        }
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.pageChanged(note.object as? PDFView) }
        })
        observers.append(center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report(.quit) }
        })
        let inputs: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged,
            .scrollWheel, .mouseMoved, .magnify
        ]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: inputs) { [weak self] event in
            MainActor.assumeIsolated { self?.inputReceived() }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFront()
                self?.report(.tick)
            }
        }
        updateFront()
    }

    /// 当前文档变化：打开（或切换到）一本书，或关闭。
    func documentChanged(_ document: PdfDocument?) {
        guard let document else {
            if openDocumentID != nil {
                openDocumentID = nil
                report(.close)
            }
            return
        }
        openDocumentID = document.id
        report(.open(
            documentId: document.id, filePath: document.filePath, fileName: document.fileName,
            pageIndex: document.lastPage
        ))
    }

    /// 阅读页 / 单词 / 笔记标签切换后重新判断阅读窗口是否在最前面。
    func updateFront() {
        guard timer != nil else { return }
        let app = NSApplication.shared
        let front = Self.isReadingWindowInFront(
            appIsActive: app.isActive, mainWindow: app.mainWindow, readerTabActive: isReaderTabActive()
        )
        guard front != lastFront else { return }
        lastFront = front
        report(.front(isFront: front))
    }

    static func isReadingWindowInFront(appIsActive: Bool, mainWindow: NSWindow?, readerTabActive: Bool) -> Bool {
        guard appIsActive, readerTabActive, let mainWindow else { return false }
        return mainWindow.frameAutosaveName == mainWindowAutosaveName && !mainWindow.isMiniaturized
    }

    private func inputReceived() {
        let now = Date()
        guard now.timeIntervalSince(lastInputReport) >= Self.inputThrottle else { return }
        lastInputReport = now
        report(.input)
    }

    private func pageChanged(_ view: PDFView?) {
        guard openDocumentID != nil,
              let view, view.window?.frameAutosaveName == Self.mainWindowAutosaveName,
              let page = view.currentPage, let index = view.document?.index(for: page), index >= 0
        else { return }
        report(.page(pageIndex: UInt32(index)))
    }
}
