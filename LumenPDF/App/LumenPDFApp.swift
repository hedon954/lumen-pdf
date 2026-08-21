import SwiftUI
import AppKit

@main
struct LumenPDFApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .background(
                    WindowFramePersistence(restorationStore: .shared)
                )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    appState.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("查找…") {
                    presentWorkspaceSearchIfMainWindow()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .background(
                    SettingsWindowConfigurator(minimumSize: NSSize(width: 860, height: 600))
                )
        }
        .defaultSize(width: 940, height: 680)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    }
}

private func presentWorkspaceSearchIfMainWindow() {
    if let key = NSApp.keyWindow, key.frameAutosaveName == "LumenPDFSettings" {
        return
    }
    ReaderEventBus.shared.postPresentWorkspaceSearch()
}

private struct WindowFramePersistence: NSViewRepresentable {
    let restorationStore: ReadingRestorationStore
    private let autosaveName = "LumenPDFMainWindow"

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        nsView.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowAttachmentView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(autosaveName: autosaveName, restorationStore: restorationStore)
    }

    final class WindowAttachmentView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject {
        private let autosaveName: String
        private let restorationStore: ReadingRestorationStore
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var restoreWorkItem: DispatchWorkItem?
        private var layoutRestoreCompletionWorkItem: DispatchWorkItem?

        init(autosaveName: String, restorationStore: ReadingRestorationStore) {
            self.autosaveName = autosaveName
            self.restorationStore = restorationStore
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            guard let window else { return }
            self.window = window
            restorationStore.beginLayoutRestoration()

            let workItem = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.restoreFrame(of: window)
                self.startObserving(window)
                self.scheduleLayoutRestoreCompletion(for: window)
            }
            restoreWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func detach() {
            restoreWorkItem?.cancel()
            restoreWorkItem = nil
            layoutRestoreCompletionWorkItem?.cancel()
            layoutRestoreCompletionWorkItem = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let window {
                restorationStore.beginLayoutRestoration()
                saveFrame(of: window)
            }
            window = nil
        }

        private func restoreFrame(of window: NSWindow) {
            _ = window.setFrameAutosaveName(autosaveName)

            var restored = false
            if let savedFrame = restorationStore.state.windowFrame?.nsRect,
               let visibleFrame = MainWindowFramePolicy.visibleFrame(
                       for: savedFrame,
                       minimumSize: window.minSize,
                       screenFrames: NSScreen.screens.map(\.visibleFrame),
                       fallbackScreenFrame: NSScreen.main?.visibleFrame
               ) {
                window.setFrame(visibleFrame, display: false)
                restored = true
            }
            if !restored {
                restored = window.setFrameUsingName(autosaveName, force: true)
            }

            guard restored,
                  let visibleFrame = MainWindowFramePolicy.visibleFrame(
                      for: window.frame,
                      minimumSize: window.minSize,
                      screenFrames: NSScreen.screens.map(\.visibleFrame),
                      fallbackScreenFrame: NSScreen.main?.visibleFrame
                  ) else { return }
            window.setFrame(visibleFrame, display: true)
        }

        private func startObserving(_ window: NSWindow) {
            let center = NotificationCenter.default
            let stableFrameNotifications: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didMoveNotification,
                NSWindow.didExitFullScreenNotification
            ]
            observers += stableFrameNotifications.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.saveFrame(of: window)
                }
            }
            observers.append(
                center.addObserver(
                    forName: NSWindow.willMiniaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.freezeLayoutCapture()
                    self.saveFrame(of: window)
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window, self.window === window else { return }
                    self.restorationStore.beginLayoutRestoration()
                    self.scheduleLayoutRestoreCompletion(for: window)
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.freezeLayoutCapture()
                    self.saveFrame(of: window)
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.freezeLayoutCapture()
                    self.saveFrame(of: window)
                }
            )
        }

        private func freezeLayoutCapture() {
            layoutRestoreCompletionWorkItem?.cancel()
            layoutRestoreCompletionWorkItem = nil
            restorationStore.beginLayoutRestoration()
        }

        private func scheduleLayoutRestoreCompletion(for window: NSWindow) {
            layoutRestoreCompletionWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      !window.isMiniaturized else { return }
                self.restorationStore.finishLayoutRestoration()
            }
            layoutRestoreCompletionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
        }

        private func saveFrame(of window: NSWindow) {
            guard !window.styleMask.contains(.fullScreen),
                  !window.isMiniaturized else { return }
            window.saveFrame(usingName: autosaveName)
            restorationStore.updateWindowFrame(window.frame)
        }

        deinit {
            restoreWorkItem?.cancel()
            layoutRestoreCompletionWorkItem?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    let minimumSize: NSSize

    func makeNSView(context: Context) -> SettingsWindowAttachmentView {
        let view = SettingsWindowAttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(window, minimumSize: minimumSize)
        }
        return view
    }

    func updateNSView(_ nsView: SettingsWindowAttachmentView, context: Context) {
        nsView.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(window, minimumSize: minimumSize)
        }
        context.coordinator.attach(nsView.window, minimumSize: minimumSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var didRestoreFrame = false

        func attach(_ window: NSWindow?, minimumSize: NSSize) {
            guard let window else { return }
            if self.window !== window {
                self.window = window
                didRestoreFrame = false
            }
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(
                width: max(window.minSize.width, minimumSize.width),
                height: max(window.minSize.height, minimumSize.height)
            )
            _ = window.setFrameAutosaveName("LumenPDFSettings")
            guard !didRestoreFrame else { return }
            didRestoreFrame = true
            _ = window.setFrameUsingName("LumenPDFSettings")
        }
    }
}

private final class SettingsWindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private enum MainWindowFramePolicy {
    static func visibleFrame(
        for savedFrame: NSRect,
        minimumSize: NSSize,
        screenFrames: [NSRect],
        fallbackScreenFrame: NSRect?
    ) -> NSRect? {
        guard !savedFrame.isEmpty else { return nil }
        let fallback = fallbackScreenFrame ?? screenFrames.first
        guard let targetScreen = bestScreen(
            for: savedFrame,
            screenFrames: screenFrames,
            fallback: fallback
        ) else { return nil }

        let width = min(
            max(savedFrame.width, minimumSize.width),
            targetScreen.width
        )
        let height = min(
            max(savedFrame.height, minimumSize.height),
            targetScreen.height
        )
        return NSRect(
            x: min(max(savedFrame.minX, targetScreen.minX), targetScreen.maxX - width),
            y: min(max(savedFrame.minY, targetScreen.minY), targetScreen.maxY - height),
            width: width,
            height: height
        )
    }

    private static func bestScreen(
        for frame: NSRect,
        screenFrames: [NSRect],
        fallback: NSRect?
    ) -> NSRect? {
        let intersections = screenFrames.map { screen in
            (screen: screen, area: intersectionArea(frame, screen))
        }
        guard let best = intersections.max(by: { $0.area < $1.area }),
              best.area > 0 else { return fallback }
        return best.screen
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
