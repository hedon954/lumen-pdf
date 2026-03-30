import Foundation
import PDFKit

/// PDF 标注持久化服务：将 Annotation 写入 PDF 文件元数据
class AnnotationPersistenceService {
    static let shared = AnnotationPersistenceService()

    private init() {}

    /// 保存标注到 PDF 文件（异步，返回是否成功）
    @discardableResult
    func saveAnnotations(for document: PDFDocument, filePath: String) async -> Bool {
        guard let url = resolveAccessibleURL(filePath: filePath) else { return false }

        // Write the document with annotations to the file
        return document.write(to: url)
    }

    /// 从 PDF 文件恢复标注关联（加载时调用）
    func loadAnnotations(from document: PDFDocument, filePath: String) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for ann in page.annotations {
                // 根据 contents 字段判断标注类型
                parseAnnotationContents(ann, page: pageIndex, filePath: filePath)
            }
        }
    }

    private func parseAnnotationContents(_ ann: PDFAnnotation, page: Int, filePath: String) {
        guard let contents = ann.contents else { return }

        // vocab:{id} → 词汇高亮，写入数据库关联
        if contents.hasPrefix("vocab:") {
            let entryId = String(contents.dropFirst(6))
            // 更新数据库中的 annotation_id 字段
            try? BridgeService.shared.updateVocabularyAnnotation(id: entryId, annotationId: ann.userName ?? "")
        }
        // free:highlight / free:underline → 自由标注，已在 PDF 中
    }

    private func resolveAccessibleURL(filePath: String) -> URL? {
        let url = URL(fileURLWithPath: filePath)
        // 尝试直接访问
        if PDFDocument(url: url) != nil { return url }
        // Security-Scoped Bookmark fallback
        if let data = UserDefaults.standard.data(forKey: "bm_\(filePath)") {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = resolved.startAccessingSecurityScopedResource()
                return resolved
            }
        }
        return nil
    }
}
