import SwiftUI
import AppKit

enum TranslationAppearance {
    /// The default keeps the bright pink used by the translation popover today.
    static let defaultAccentHex = "#FF2D92"

    static func color(from hex: String) -> Color {
        Color(nsColor: NSColor(hex: hex) ?? .controlAccentColor)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else { return nil }

        let red = CGFloat((number >> (value.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((number >> (value.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((number >> (value.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = value.count == 8 ? CGFloat(number & 0xFF) / 255 : 1
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()),
            Int((alpha * 255).rounded())
        )
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
