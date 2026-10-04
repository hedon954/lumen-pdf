import Foundation

extension PdfDocument {
    /// `path` 是这本书的书库副本，或复制进书库之前的原文件。
    func matches(path: String) -> Bool {
        filePath == path || originalPath == path
    }

    /// 文件不在了：通常是还没复制进书库、原文件又被移走的旧书。仍留在文库里，等文件回来。
    var isFileMissing: Bool {
        !FileManager.default.fileExists(atPath: filePath)
    }
}
