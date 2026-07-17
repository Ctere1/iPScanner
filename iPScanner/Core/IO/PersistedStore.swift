import Foundation

/// Reads and writes the two things iPScanner remembers between launches: host labels and saved
/// ranges.
///
/// Takes its `UserDefaults` rather than reaching for `.standard`, following ColumnVisibility — a
/// test hands it a throwaway suite instead of writing into the real app's saved state. The static
/// form this replaces was constructed inside `ScanController.init`, which meant merely constructing
/// a controller in a test touched the developer's own defaults.
struct PersistedStore: Sendable {
    private let labelsKey = "iPScanner.labels"
    private let savedRangesKeyV1 = "iPScanner.savedRanges"
    private let savedRangesKeyV2 = "iPScanner.savedRangesV2"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLabels() -> [String: String] {
        defaults.dictionary(forKey: labelsKey) as? [String: String] ?? [:]
    }

    func saveLabels(_ labels: [String: String]) {
        if labels.isEmpty {
            defaults.removeObject(forKey: labelsKey)
        } else {
            defaults.set(labels, forKey: labelsKey)
        }
    }

    func loadRanges() -> [SavedRange] {
        if let data = defaults.data(forKey: savedRangesKeyV2),
           let decoded = try? JSONDecoder().decode([SavedRange].self, from: data) {
            return decoded
        }
        // Migration from v1 (array of plain strings).
        if let strings = defaults.stringArray(forKey: savedRangesKeyV1) {
            return strings.map { SavedRange(range: $0, name: nil) }
        }
        return []
    }

    func saveRanges(_ ranges: [SavedRange]) {
        if ranges.isEmpty {
            defaults.removeObject(forKey: savedRangesKeyV2)
            defaults.removeObject(forKey: savedRangesKeyV1)
            return
        }
        if let data = try? JSONEncoder().encode(ranges) {
            defaults.set(data, forKey: savedRangesKeyV2)
        }
        defaults.removeObject(forKey: savedRangesKeyV1)
    }
}
