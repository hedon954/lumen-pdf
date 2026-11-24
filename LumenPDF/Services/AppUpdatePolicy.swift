import Foundation

enum AppUpdatePreference {
    static let checkOnLaunch = "app_update_check_on_launch"
    static let lastSuccess = "app_update_last_success_at"
    static let lastFailure = "app_update_last_failure_at"
}

enum AutomaticUpdateCheck {
    static let successInterval: TimeInterval = 6 * 60 * 60
    static let failureBackoff: TimeInterval = 15 * 60

    static func shouldRun(
        enabled: Bool,
        suppressed: Bool,
        now: TimeInterval,
        lastSuccess: TimeInterval?,
        lastFailure: TimeInterval?
    ) -> Bool {
        if suppressed || !enabled {
            return false
        }
        if let lastSuccess, now - lastSuccess < successInterval {
            return false
        }
        if let lastFailure, now - lastFailure < failureBackoff {
            return false
        }
        return true
    }
}

struct BundleLocationFacts: Equatable, Sendable {
    var bundlePath: String
    var volumeIsReadOnly: Bool
    var parentIsWritable: Bool
}

enum AppInstallBlock: Equatable, Sendable {
    case diskImage
    case translocated
    case notWritable
}

enum AppInstallDecision: Equatable, Sendable {
    case replaceInPlace
    case blocked(AppInstallBlock)
}

enum AppInstallLocationPolicy {
    static func decide(_ facts: BundleLocationFacts) -> AppInstallDecision {
        if facts.bundlePath.contains("/AppTranslocation/") {
            return .blocked(.translocated)
        }
        if facts.volumeIsReadOnly {
            return .blocked(.diskImage)
        }
        if facts.bundlePath.isEmpty || !facts.parentIsWritable {
            return .blocked(.notWritable)
        }
        return .replaceInPlace
    }
}

enum BundleLocationReader {
    static func current(bundle: Bundle = .main) -> BundleLocationFacts {
        let url = bundle.bundleURL
        let parent = url.deletingLastPathComponent()
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return BundleLocationFacts(
            bundlePath: url.path,
            volumeIsReadOnly: readOnly,
            parentIsWritable: FileManager.default.isWritableFile(atPath: parent.path)
        )
    }
}

enum DiskImageAttach {
    static func mountPoint(in plist: Any) -> String? {
        guard let root = plist as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]] else {
            return nil
        }
        for entity in entities {
            guard let mount = entity["mount-point"] as? String else { continue }
            let trimmed = mount.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

struct UpdatePayload: Equatable, Sendable {
    var version: String
    var downloadURL: String
    var sha256: String
    var sizeBytes: UInt64

    var diskImageName: String { "LumenPDF-\(version).dmg" }
}

enum AppUpdateHousekeeping {
    static func removeLeftovers(bundle: Bundle = .main, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        let previous = bundle.bundleURL.appendingPathExtension("previous")
        if FileManager.default.fileExists(atPath: previous.path) {
            try? FileManager.default.removeItem(at: previous)
        }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in items where url.lastPathComponent.hasPrefix("LumenPDF-update-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
