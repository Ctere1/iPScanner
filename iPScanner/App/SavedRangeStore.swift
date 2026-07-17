import Foundation
import Observation

/// The ranges the user has starred, kept sorted by display title.
///
/// In App/ rather than Core/ because it is `@Observable` and the CLI takes its targets from
/// arguments, not from saved state.
@Observable
@MainActor
final class SavedRangeStore {
    private let store: PersistedStore

    private(set) var ranges: [SavedRange] = []

    init(store: PersistedStore = PersistedStore()) {
        self.store = store
        self.ranges = store.loadRanges()
        sort()
    }

    func isSaved(_ range: String) -> Bool {
        let key = range.trimmingCharacters(in: .whitespaces)
        return !key.isEmpty && ranges.contains { $0.range == key }
    }

    /// Saves `range` if it is new, removes it if it is already saved.
    func toggle(_ range: String) {
        let key = range.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        if let idx = ranges.firstIndex(where: { $0.range == key }) {
            ranges.remove(at: idx)
        } else {
            ranges.append(SavedRange(range: key, name: nil))
            sort()
        }
        store.saveRanges(ranges)
    }

    func remove(_ range: String) {
        ranges.removeAll { $0.range == range }
        store.saveRanges(ranges)
    }

    func rename(_ range: String, to name: String?) {
        guard let idx = ranges.firstIndex(where: { $0.range == range }) else { return }
        let trimmed = name?.trimmed
        ranges[idx].name = (trimmed?.isEmpty == false) ? trimmed : nil
        sort()
        store.saveRanges(ranges)
    }

    private func sort() {
        ranges.sort {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }
}
