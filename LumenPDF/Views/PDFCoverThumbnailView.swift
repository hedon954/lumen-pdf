import SwiftUI

struct PDFCoverThumbnailView: View {
    let filePath: String

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(
            width: PDFCoverThumbnailGeometry.displaySize.width,
            height: PDFCoverThumbnailGeometry.displaySize.height
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 0.5)
        .task(id: filePath) {
            image = await PDFCoverThumbnailCache.shared.thumbnail(for: filePath)
        }
    }
}
