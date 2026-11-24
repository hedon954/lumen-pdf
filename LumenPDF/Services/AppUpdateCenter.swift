import AppKit
import Combine
import Foundation

enum AppUpdateActivity: Equatable {
    case idle
    case checking
    case downloading
    case installing
}

@MainActor
final class AppUpdateCenter: ObservableObject {
    @Published private(set) var activity: AppUpdateActivity = .idle
    @Published private(set) var offer: AppUpdateOffer?
    @Published private(set) var downloadFraction: Double = 0
    @Published private(set) var statusMessage = ""
    @Published var showsBanner = false
    @Published var showsSheet = false
    @Published var checksOnLaunch: Bool {
        didSet { UserDefaults.standard.set(checksOnLaunch, forKey: AppUpdatePreference.checkOnLaunch) }
    }

    private var didStartAutomatic = false
    private var deferredVersion: String?
    private let bridge: BridgeService

    init(bridge: BridgeService = .shared) {
        self.bridge = bridge
        let stored = UserDefaults.standard.object(forKey: AppUpdatePreference.checkOnLaunch) as? Bool
        checksOnLaunch = stored ?? true
    }

    var isBusy: Bool {
        activity != .idle
    }

    static var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func startIfNeeded() {
        guard !didStartAutomatic else { return }
        didStartAutomatic = true
        AppUpdateHousekeeping.removeLeftovers()
        guard AutomaticUpdateCheck.shouldRun(
            enabled: checksOnLaunch,
            suppressed: Self.suppressesAutomaticCheck,
            now: Date().timeIntervalSince1970,
            lastSuccess: Self.timestamp(AppUpdatePreference.lastSuccess),
            lastFailure: Self.timestamp(AppUpdatePreference.lastFailure)
        ) else { return }
        Task { await self.check(automatic: true) }
    }

    func checkManually() {
        Task { await self.check(automatic: false) }
    }

    func presentDetails() {
        guard offer != nil else { return }
        if let window = NSApp.windows.first(where: { $0.frameAutosaveName == "LumenPDFMainWindow" }) {
            window.makeKeyAndOrderFront(nil)
        }
        showsSheet = true
    }

    func deferCurrentOffer() {
        deferredVersion = offer?.version
        showsBanner = false
        showsSheet = false
    }

    func installCurrentOffer() {
        guard let offer, activity == .idle else { return }
        Task { await self.install(offer) }
    }

    func cancelInstall() {
        AppUpdateInstaller.cancel()
    }

    private func check(automatic: Bool) async {
        guard activity == .idle else { return }
        activity = .checking
        statusMessage = ""
        let version = Self.currentVersion
        let status = await bridge.checkAppUpdate(currentVersion: version)
        activity = .idle
        switch status {
        case .upToDate:
            recordSuccess()
            offer = nil
            showsBanner = false
            if !automatic {
                report(AppUpdateCopy.upToDate(version), modal: true)
            }
        case .available(let offer):
            recordSuccess()
            self.offer = offer
            if automatic {
                showsBanner = deferredVersion != offer.version
            } else {
                showsBanner = true
                presentDetails()
            }
        case .failed(let reason):
            recordFailure()
            if !automatic {
                report(AppUpdateCopy.failure(reason), modal: true)
            }
        }
    }

    private func install(_ offer: AppUpdateOffer) async {
        AppUpdateInstaller.begin()
        activity = .downloading
        downloadFraction = 0
        statusMessage = ""
        let payload = UpdatePayload(
            version: offer.version,
            downloadURL: offer.downloadUrl,
            sha256: offer.sha256,
            sizeBytes: offer.sizeBytes
        )
        do {
            let relaunch = try await AppUpdateInstaller.install(
                payload: payload,
                facts: BundleLocationReader.current(),
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.downloadFraction = fraction
                    }
                }
            )
            if relaunch {
                activity = .installing
                NSApp.terminate(nil)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 35_000_000_000)
                    guard self.activity == .installing else { return }
                    self.activity = .idle
                    self.report(
                        AppUpdateCopy.installFailure(.replaceFailed),
                        modal: !self.showsSheet
                    )
                }
            }
        } catch let failure as AppUpdateInstallFailure {
            activity = .idle
            guard !isCancellation(failure) else { return }
            report(AppUpdateCopy.installFailure(failure), modal: !showsSheet)
        } catch {
            activity = .idle
            report(AppUpdateCopy.installFailure(.downloadFailed), modal: !showsSheet)
        }
    }

    private func report(_ message: String, modal: Bool) {
        statusMessage = message
        guard modal else { return }
        if NSApp.keyWindow?.frameAutosaveName == "LumenPDFSettings" {
            return
        }
        let alert = NSAlert()
        alert.messageText = "更新"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    private func recordSuccess() {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: AppUpdatePreference.lastSuccess)
        UserDefaults.standard.removeObject(forKey: AppUpdatePreference.lastFailure)
    }

    private func recordFailure() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppUpdatePreference.lastFailure)
    }

    private func isCancellation(_ failure: AppUpdateInstallFailure) -> Bool {
        if case .cancelled = failure {
            return true
        }
        return false
    }

    private static var suppressesAutomaticCheck: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--uitesting") }
    }

    private static func timestamp(_ key: String) -> TimeInterval? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : nil
    }
}
