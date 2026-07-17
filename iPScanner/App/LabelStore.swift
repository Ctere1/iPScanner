import Foundation
import Observation

/// User-assigned host labels, keyed by anchor.
///
/// In App/ rather than Core/ because it is `@Observable` and the CLI has no concept of a label.
@Observable
@MainActor
final class LabelStore {
    private let store: PersistedStore

    private(set) var labels: [String: String] = [:]

    init(store: PersistedStore = PersistedStore()) {
        self.store = store
        self.labels = store.loadLabels()
    }

    /// MAC if we have one, IP otherwise.
    ///
    /// A MAC survives the DHCP lease changing under a host; an IP does not. Falling back to IP is
    /// the best available for a host whose MAC we never learned — it is off-subnet, or the ARP
    /// cache had not caught up.
    nonisolated func anchor(for host: Host) -> String {
        host.mac ?? host.ip
    }

    func label(for host: Host) -> String? {
        labels[anchor(for: host)]
    }

    func setLabel(_ value: String?, for host: Host) {
        setLabel(value, forAnchor: anchor(for: host))
    }

    /// Labels are keyed by anchor, so an editor that captured the anchor when editing began can
    /// commit safely even after the selection has moved on or the host is gone from the table.
    func setLabel(_ value: String?, forAnchor key: String) {
        let trimmed = value?.trimmed
        if let trimmed, !trimmed.isEmpty {
            labels[key] = trimmed
        } else {
            labels.removeValue(forKey: key)
        }
        store.saveLabels(labels)
    }

    /// Folds labels from a restored snapshot in, without overwriting what the user has now.
    ///
    /// A snapshot carries the labels as they were when it was taken. Letting it win would mean
    /// opening an old file silently reverts a label renamed since — so the current one stays and
    /// only anchors with no label today are filled in.
    func merge(_ incoming: [String: String]) {
        for (key, value) in incoming where labels[key] == nil {
            labels[key] = value
        }
        store.saveLabels(labels)
    }
}
