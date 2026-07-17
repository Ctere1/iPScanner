import Foundation

struct SavedRange: Codable, Hashable, Identifiable {
    var range: String
    var name: String?

    var id: String { range }

    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return range
    }
}
