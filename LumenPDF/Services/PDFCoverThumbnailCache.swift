import AppKit
import Foundation
import PDFKit

enum PDFCoverThumbnailGeometry {
    static let displaySize = CGSize(width: 36, height: 48)
    static let renderScale: CGFloat = 2

    static func aspectFit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func pixelSize(
        pageSize: CGSize,
        fitting: CGSize = displaySize,
        scale: CGFloat = renderScale
    ) -> CGSize {
        let fitted = aspectFit(pageSize, in: fitting)
        return CGSize(
            width: max(1, (fitted.width * scale).rounded()),
            height: max(1, (fitted.height * scale).rounded())
        )
    }

    static func cacheKey(filePath: String, modificationDate: Date?) -> String {
        let stamp = modificationDate.map { String($0.timeIntervalSince1970) } ?? "0"
        return "\(filePath)|\(stamp)"
    }
}

@MainActor
final class PDFCoverThumbnailCache {
    static let shared = PDFCoverThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    func thumbnail(for filePath: String) async -> NSImage? {
        let key = Self.cacheKey(for: filePath)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> { @MainActor in
            if let cached = self.cache.object(forKey: key as NSString) {
                return cached
            }
            await Task.yield()
            let image = Self.render(filePath: filePath)
            if let image {
                self.cache.setObject(image, forKey: key as NSString)
            }
            return image
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        return image
    }

    private static func cacheKey(for filePath: String) -> String {
        let url = URL(fileURLWithPath: filePath)
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        return PDFCoverThumbnailGeometry.cacheKey(filePath: filePath, modificationDate: modified)
    }

    private static func render(filePath: String) -> NSImage? {
        guard let document = PDFKitView.loadDocument(filePath: filePath),
              let page = document.page(at: 0)
        else {
            return nil
        }
        let pageSize = page.bounds(for: .mediaBox).size
        let pixelSize = PDFCoverThumbnailGeometry.pixelSize(pageSize: pageSize)
        return page.thumbnail(of: pixelSize, for: .mediaBox)
    }
}
