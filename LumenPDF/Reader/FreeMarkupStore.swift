import Foundation

/// Free highlight / underline persistence lives outside the user's PDF file:
/// these annotations are stored in `UserDefaults` keyed by file path and re-applied on load.
enum FreeMarkupStore {
    struct Item: Codable, Equatable {
        let page: Int
        let boundsStr: String
        /// "highlight" or "underline"
        let type: String
    }

    private static func key(for filePath: String) -> String { "freemarks::\(filePath)" }

    static func load(_ filePath: String, defaults: UserDefaults = .standard) -> [Item] {
        guard !filePath.isEmpty,
              let data = defaults.data(forKey: key(for: filePath)),
              let items = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ filePath: String, items: [Item], defaults: UserDefaults = .standard) {
        guard !filePath.isEmpty else { return }
        let key = key(for: filePath)
        if items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
