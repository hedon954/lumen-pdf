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

struct LibraryShelfImportNode: Equatable {
    var name: String
    var pdfs: [LibraryFolderPDF]
    var children: [LibraryShelfImportNode]
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

    /// 把这次要加入的 PDF 收成一棵书架。根节点的名字是所选文件夹。
    /// 不包含子文件夹时，只有直接放在根目录的 PDF。
    static func shelfTree(
        rootPath: String,
        rootName: String,
        pdfs: [LibraryFolderPDF],
        includingSubfolders: Bool
    ) -> LibraryShelfImportNode {
        let root = standardized(rootPath)
        var node = LibraryShelfImportNode(name: rootName, pdfs: [], children: [])
        let sorted = pdfs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        for pdf in sorted {
            let path = standardized(pdf.path)
            guard path.hasPrefix(root + "/") else { continue }
            let relative = String(path.dropFirst(root.count + 1))
            let parts = relative.split(separator: "/").map(String.init)
            guard let fileName = parts.last, !fileName.isEmpty else { continue }
            let folders = parts.dropLast()
            if !includingSubfolders && !folders.isEmpty { continue }
            insert(pdf, folders: Array(folders), into: &node)
        }
        sortTree(&node)
        return node
    }

    private static func insert(
        _ pdf: LibraryFolderPDF,
        folders: [String],
        into node: inout LibraryShelfImportNode
    ) {
        guard let name = folders.first else {
            node.pdfs.append(pdf)
            return
        }
        if let index = node.children.firstIndex(where: { $0.name == name }) {
            insert(pdf, folders: Array(folders.dropFirst()), into: &node.children[index])
        } else {
            node.children.append(LibraryShelfImportNode(name: name, pdfs: [], children: []))
            let index = node.children.count - 1
            insert(pdf, folders: Array(folders.dropFirst()), into: &node.children[index])
        }
    }

    private static func sortTree(_ node: inout LibraryShelfImportNode) {
        node.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for index in node.children.indices {
            sortTree(&node.children[index])
        }
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
