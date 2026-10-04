import XCTest
@testable import LumenPDF

final class LibraryFolderImportTests: XCTestCase {
    func testImportablePDFsKeepRegularPDFFilesInPathOrder() {
        let entries = [
            entry(path: "/books/b.PDF", fileName: "b.PDF"),
            entry(path: "/books/a.pdf", fileName: "a.pdf"),
            entry(path: "/books/note.txt", fileName: "note.txt"),
            entry(path: "/books/a.pdf", fileName: "a.pdf")
        ]

        let pdfs = LibraryFolderImporter.importablePDFs(in: entries)

        XCTAssertEqual(pdfs, [
            LibraryFolderPDF(path: "/books/a.pdf", fileName: "a.pdf"),
            LibraryFolderPDF(path: "/books/b.PDF", fileName: "b.PDF")
        ])
    }

    func testImportablePDFsSkipSymlinksDirectoriesAndNonFiles() {
        let entries = [
            entry(path: "/books/link.pdf", fileName: "link.pdf", isSymbolicLink: true),
            entry(path: "/books/folder.pdf", fileName: "folder.pdf", isRegularFile: false, isDirectory: true),
            entry(path: "/books/missing.pdf", fileName: "missing.pdf", isRegularFile: false)
        ]

        XCTAssertEqual(LibraryFolderImporter.importablePDFs(in: entries), [])
    }

    func testPartitionLeavesExistingDocumentsOutOfTheInsertList() {
        let pdfs = [
            LibraryFolderPDF(path: "/books/old.pdf", fileName: "old.pdf"),
            LibraryFolderPDF(path: "/books/new.pdf", fileName: "new.pdf")
        ]

        let partition = LibraryFolderImporter.partition(pdfs, existingPaths: ["/books/old.pdf"])

        XCTAssertEqual(partition.adding, [LibraryFolderPDF(path: "/books/new.pdf", fileName: "new.pdf")])
        XCTAssertEqual(partition.alreadyPresent, 1)
    }

    func testNestedPDFsStayOutUnlessSubfoldersAreIncluded() {
        let entries = [
            entry(path: "/books/a.pdf", fileName: "a.pdf"),
            entry(path: "/books/ch/b.pdf", fileName: "b.pdf", isNested: true)
        ]

        XCTAssertEqual(
            LibraryFolderImporter.importablePDFs(in: entries).map(\.path),
            ["/books/a.pdf"]
        )
        XCTAssertEqual(
            LibraryFolderImporter.importablePDFs(in: entries, includingSubfolders: true).map(\.path),
            ["/books/a.pdf", "/books/ch/b.pdf"]
        )
    }

    private func entry(
        path: String,
        fileName: String,
        isRegularFile: Bool = true,
        isSymbolicLink: Bool = false,
        isDirectory: Bool = false,
        isNested: Bool = false
    ) -> LibraryFolderEntry {
        LibraryFolderEntry(
            path: path,
            fileName: fileName,
            isRegularFile: isRegularFile,
            isSymbolicLink: isSymbolicLink,
            isDirectory: isDirectory,
            isNested: isNested
        )
    }
}
