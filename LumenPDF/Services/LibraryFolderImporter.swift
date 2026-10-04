import Foundation

struct LibraryFolderEntry: Equatable, Sendable {
    var path: String
    var fileName: String
    var isRegularFile: Bool
    var isSymbolicLink: Bool
    var isDirectory: Bool
    /// True when the file is inside a subfolder of the selected directory.
    var isNested: Bool
}

struct LibraryFolderPDF: Equatable, Sendable {
    var path: String
    var fileName: String
}

struct CollectedLibraryPDF: Sendable {
    var pdf: LibraryFolderPDF
    var bookmark: Data?
}

struct LibraryFolderImportPartition: Equatable {
    var adding: [LibraryFolderPDF]
    var alreadyPresent: Int
}

enum LibraryFolderImporter {
    static func importablePDFs(
        in entries: [LibraryFolderEntry],
        includingSubfolders: Bool = false
    ) -> [LibraryFolderPDF] {
        var seen = Set<String>()
        var result: [LibraryFolderPDF] = []
        for entry in entries {
            guard includingSubfolders || !entry.isNested else { continue }
            guard entry.isRegularFile, !entry.isSymbolicLink, !entry.isDirectory else { continue }
            guard isPDFFileName(entry.fileName) else { continue }
            guard seen.insert(entry.path).inserted else { continue }
            result.append(LibraryFolderPDF(path: entry.path, fileName: entry.fileName))
        }
        result.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return result
    }

    static func partition(
        _ pdfs: [LibraryFolderPDF],
        existingPaths: Set<String>
    ) -> LibraryFolderImportPartition {
        var adding: [LibraryFolderPDF] = []
        var alreadyPresent = 0
        for pdf in pdfs {
            if existingPaths.contains(pdf.path) {
                alreadyPresent += 1
            } else {
                adding.append(pdf)
            }
        }
        return LibraryFolderImportPartition(adding: adding, alreadyPresent: alreadyPresent)
    }

    /// Enumerate `folder` while its security scope is still active. Bookmarks are created
    /// only for paths that were not already in the library at the start of the scan.
    static func collectPDFs(
        in folder: URL,
        existingPaths: Set<String>,
        includingSubfolders: Bool
    ) -> [CollectedLibraryPDF] {
        let scanned = scan(folder, includingSubfolders: includingSubfolders)
        let urlsByPath = Dictionary(scanned.map { ($0.entry.path, $0.url) }, uniquingKeysWith: { first, _ in first })
        return importablePDFs(
            in: scanned.map(\.entry),
            includingSubfolders: includingSubfolders
        ).map { pdf in
            let bookmark: Data?
            if existingPaths.contains(pdf.path) {
                bookmark = nil
            } else {
                bookmark = urlsByPath[pdf.path].flatMap(bookmarkData(for:))
            }
            return CollectedLibraryPDF(pdf: pdf, bookmark: bookmark)
        }
    }

    static func bookmarkData(for url: URL) -> Data? {
        (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? (try? url.bookmarkData())
    }

    private struct ScannedEntry {
        var entry: LibraryFolderEntry
        var url: URL
    }

    private static func scan(_ folder: URL, includingSubfolders: Bool) -> [ScannedEntry] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        let root = folder.standardizedFileURL.path
        if !includingSubfolders {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )) ?? []
            return urls.compactMap { scannedEntry(for: $0, keys: keys, isNested: false) }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var scanned: [ScannedEntry] = []
        for case let url as URL in enumerator {
            let parent = url.deletingLastPathComponent().standardizedFileURL.path
            guard let entry = scannedEntry(for: url, keys: keys, isNested: parent != root) else { continue }
            scanned.append(entry)
        }
        return scanned
    }

    private static func scannedEntry(
        for url: URL,
        keys: Set<URLResourceKey>,
        isNested: Bool
    ) -> ScannedEntry? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        let values = try? url.resourceValues(forKeys: keys)
        return ScannedEntry(
            entry: LibraryFolderEntry(
                path: url.path,
                fileName: url.lastPathComponent,
                isRegularFile: values?.isRegularFile == true,
                isSymbolicLink: values?.isSymbolicLink == true,
                isDirectory: values?.isDirectory == true,
                isNested: isNested
            ),
            url: url
        )
    }

    private static func isPDFFileName(_ fileName: String) -> Bool {
        (fileName as NSString).pathExtension.lowercased() == "pdf"
    }
}
