import SwiftUI

struct PDFCoverThumbnailView: View {
    let filePath: String
    var size: CGSize = PDFCoverThumbnailGeometry.displaySize
    var showsCurrent = false

    @State private var image: NSImage?

    var body: some View {
        cover
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .contentShape(Rectangle())
            .task(id: "\(filePath)|\(size.width)|\(size.height)") {
                image = await PDFCoverThumbnailCache.shared.thumbnail(for: filePath, fitting: size)
            }
    }

    @ViewBuilder
    private var cover: some View {
        if let image {
            let fitted = PDFCoverThumbnailGeometry.aspectFit(image.size, in: size)
            Image(nsImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .overlay(alignment: .topTrailing) { currentMark }
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
        } else {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var currentMark: some View {
        if showsCurrent {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .padding(6)
        }
    }

}

enum ShelfReadStamp {
    static func text(unixSeconds: Int64, now: Date = Date(), calendar: Calendar = .current) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        if calendar.isDate(date, inSameDayAs: now) {
            return clock(date, calendar: calendar)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(clock(date, calendar: calendar))"
        }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return "\(month)月\(day)日"
        }
        let year = calendar.component(.year, from: date)
        return "\(year)/\(month)/\(day)"
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
