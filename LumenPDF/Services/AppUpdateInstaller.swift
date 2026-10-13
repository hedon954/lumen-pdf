import AppKit
import CryptoKit
import Foundation

enum AppUpdateInstallFailure: Error {
    case untrustedURL
    case downloadFailed
    case checksumMismatch
    case mountFailed(publishedToDownloads: Bool)
    case bundleMissing
    case versionMismatch
    case locationBlocked(AppInstallBlock, publishedToDownloads: Bool)
    case replaceFailed
    case cancelled
}

enum AppUpdateInstaller {
    private static let session = InstallSession()

    static func begin() {
        session.begin()
    }

    static func cancel() {
        session.cancel()
    }

    static func install(
        payload: UpdatePayload,
        facts: BundleLocationFacts,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            try await session.install(payload: payload, facts: facts, onProgress: onProgress)
        }.value
    }
}

private final class InstallSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionTask?

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func begin() {
        lock.lock()
        cancelled = false
        task = nil
        lock.unlock()
    }

    func install(
        payload: UpdatePayload,
        facts: BundleLocationFacts,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Bool {
        let root = stagingRoot(for: payload.version)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent(payload.diskImageName)
        do {
            try await download(payload, to: imageURL, onProgress: onProgress)
            try throwIfCancelled()
            let digest = try UpdateDigest.sha256Hex(of: imageURL)
            guard digest == payload.sha256.lowercased() else {
                try? FileManager.default.removeItem(at: imageURL)
                throw AppUpdateInstallFailure.checksumMismatch
            }
            try throwIfCancelled()
            if case let .blocked(reason) = AppInstallLocationPolicy.decide(facts) {
                let published = await publishDiskImage(at: imageURL, name: payload.diskImageName)
                throw AppUpdateInstallFailure.locationBlocked(reason, publishedToDownloads: published)
            }
            try await stageInstalledApp(from: imageURL, version: payload.version, root: root)
            try throwIfCancelled()
            let staged = root.appendingPathComponent("LumenPDF.app", isDirectory: true)
            try launchSwap(target: facts.bundlePath, staged: staged)
            return true
        } catch {
            if error is AppUpdateInstallFailure {
                throw error
            }
            throw AppUpdateInstallFailure.downloadFailed
        }
    }

    private func throwIfCancelled() throws {
        lock.lock()
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled {
            throw AppUpdateInstallFailure.cancelled
        }
    }

    private func download(
        _ payload: UpdatePayload,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: payload.downloadURL),
              BridgeService.shared.isOfficialReleaseAssetURL(payload.downloadURL, fileName: payload.diskImageName) else {
            throw AppUpdateInstallFailure.untrustedURL
        }
        let downloader = DiskImageDownload(expectedBytes: payload.sizeBytes, onProgress: onProgress)
        try throwIfCancelled()
        try await downloader.save(url, to: destination) { [weak self] task in
            self?.track(task)
        }
    }

    private func track(_ task: URLSessionTask) {
        lock.lock()
        let shouldCancel = cancelled
        self.task = task
        lock.unlock()
        if shouldCancel {
            task.cancel()
        } else {
            task.resume()
        }
    }

    private func stageInstalledApp(from imageURL: URL, version: String, root: URL) async throws {
        let attached = runCommand(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-plist", imageURL.path]
        )
        guard attached.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: attached.output, options: [], format: nil),
              let mount = DiskImageAttach.mountPoint(in: plist) else {
            let published = await publishDiskImage(at: imageURL, name: imageURL.lastPathComponent)
            throw AppUpdateInstallFailure.mountFailed(publishedToDownloads: published)
        }
        defer { detach(mount) }

        let source = URL(fileURLWithPath: mount, isDirectory: true)
            .appendingPathComponent("LumenPDF.app", isDirectory: true)
        let executable = source.appendingPathComponent("Contents/MacOS/LumenPDF")
        guard FileManager.default.fileExists(atPath: executable.path),
              shortVersion(ofApp: source) == version else {
            if shortVersion(ofApp: source) == nil || !FileManager.default.fileExists(atPath: executable.path) {
                throw AppUpdateInstallFailure.bundleMissing
            }
            throw AppUpdateInstallFailure.versionMismatch
        }

        let staged = root.appendingPathComponent("LumenPDF.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        let copied = runCommand("/usr/bin/ditto", [source.path, staged.path])
        guard copied.status == 0 else {
            throw AppUpdateInstallFailure.replaceFailed
        }
    }

    private func launchSwap(target: String, staged: URL) throws {
        let script = staged.deletingLastPathComponent().appendingPathComponent("swap.sh")
        try SwapScript.contents.write(to: script, atomically: true, encoding: .utf8)
        let log = try prepareLog()
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = [
            "/bin/bash",
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            target,
            staged.path
        ]
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AppUpdateInstallFailure.replaceFailed
        }
        SwapProcessBox.process = process
    }

    private func publishDiskImage(at source: URL, name: String) async -> Bool {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return false
        }
        let destination = downloads.appendingPathComponent(name)
        let published: URL
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            published = destination
        } catch {
            published = source
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([published])
            }
            return false
        }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([published])
        }
        return true
    }

    private func stagingRoot(for version: String) -> URL {
        let safe = version.filter { $0.isNumber || $0 == "." }
        let name = safe.isEmpty ? "LumenPDF-update" : "LumenPDF-update-\(safe)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }

    private func prepareLog() throws -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("Logs/LumenPDF", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("update.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        return log
    }

    private func detach(_ mount: String) {
        let quiet = runCommand("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
        if quiet.status != 0 {
            _ = runCommand("/usr/bin/hdiutil", ["detach", mount, "-force"])
        }
    }

    private func shortVersion(ofApp app: URL) -> String? {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = object as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            return nil
        }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func runCommand(_ launchPath: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return CommandResult(status: 1, output: Data())
        }
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            output: stdout.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

private struct CommandResult {
    var status: Int32
    var output: Data
}

private enum UpdateDigest {
    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private enum SwapScript {
    static let contents = """
    #!/bin/bash
    set -euo pipefail
    pid="$1"
    target="$2"
    staged="$3"
    backup="${target}.previous"

    echo "waiting for ${pid}"
    deadline=$((SECONDS + 30))
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "timed out waiting for ${pid}"
            exit 1
        fi
        sleep 0.2
    done
    sleep 0.4

    rm -rf "$backup"
    if [ -d "$target" ]; then
        mv "$target" "$backup"
    fi
    if ! /usr/bin/ditto "$staged" "$target"; then
        rm -rf "$target"
        if [ -d "$backup" ]; then
            mv "$backup" "$target"
        fi
        exit 1
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$target" || true
    rm -rf "$backup"
    echo "relaunching ${target}"
    /usr/bin/open "$target"
    """
}

private enum SwapProcessBox {
    static var process: Process?
}

private final class DiskImageDownload: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private let expectedBytes: UInt64
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var rejectedRedirect = false
    private var didFinish = false
    private var session: URLSession?

    init(expectedBytes: UInt64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func save(
        _ url: URL,
        to destination: URL,
        onTask: (URLSessionTask) -> Void
    ) async throws {
        self.destination = destination
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.continuation = continuation
            onTask(session.downloadTask(with: url))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : Double(expectedBytes)
        guard total > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        didFinish = true
        guard let destination else {
            finish(.failure(AppUpdateInstallFailure.downloadFailed))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(AppUpdateInstallFailure.downloadFailed))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            if rejectedRedirect {
                finish(.failure(AppUpdateInstallFailure.untrustedURL))
            } else if let urlError = error as? URLError, urlError.code == .cancelled {
                finish(.failure(AppUpdateInstallFailure.cancelled))
            } else {
                finish(.failure(AppUpdateInstallFailure.downloadFailed))
            }
        } else if !didFinish {
            finish(.failure(AppUpdateInstallFailure.downloadFailed))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              BridgeService.shared.isTrustedUpdateURL(url.absoluteString) else {
            rejectedRedirect = true
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
