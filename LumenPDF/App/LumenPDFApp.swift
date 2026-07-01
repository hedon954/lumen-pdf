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
                .background(WindowFramePersistence())
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    appState.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}


private struct WindowFramePersistence: NSViewRepresentable {
    private let frameKey = "main_window_frame"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(frameKey: frameKey) }

    final class Coordinator: NSObject {
        private let frameKey: String
        private weak var window: NSWindow?

        init(frameKey: String) { self.frameKey = frameKey }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            window.setFrameAutosaveName("LumenPDFMainWindow")
            if let saved = UserDefaults.standard.string(forKey: frameKey) {
                let frame = NSRectFromString(saved)
                if !frame.isEmpty {
                    window.setFrame(frame, display: true)
                }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(saveFrame(_:)),
                name: NSWindow.willCloseNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(saveFrame(_:)),
                name: NSWindow.didEndLiveResizeNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(saveFrame(_:)),
                name: NSWindow.didMoveNotification, object: window
            )
        }

        @objc private func saveFrame(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
