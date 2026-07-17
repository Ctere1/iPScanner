import Foundation
import Observation
import SwiftUI

/// Which optional table columns are shown, and the one definition of what "default" means.
///
/// Lives in `UIState/` rather than `Models/` on purpose: the `ipscanner` CLI target compiles
/// `Models/` and `Services/` (see project.yml), and this is UI-only state.
///
/// Previously eight `@AppStorage` properties on `ContentView`, with the defaults written out three
/// times — the declarations, "Show All", and "Reset to Default" — which had already drifted.
@Observable
@MainActor
final class ColumnVisibility {
    enum Column: String, CaseIterable, Identifiable {
        case label, hostname, mac, vendor, title, rtt, ttl, ports

        var id: String { rawValue }

        var title: String {
            switch self {
            case .label: "Label"
            case .hostname: "Hostname"
            case .mac: "MAC"
            case .vendor: "Vendor"
            case .title: "Title"
            case .rtt: "RTT"
            case .ttl: "TTL"
            case .ports: "Ports"
            }
        }

        /// Unchanged from the `@AppStorage` keys this replaces, so nobody's saved layout resets.
        var storageKey: String { "iPScanner.col.\(rawValue)" }

        /// The single source of truth. MAC is on: it is a network scanner's primary identifier,
        /// and Vendor — which is derived from it — was already shown by default.
        static let defaults: Set<Column> = [.label, .hostname, .mac, .vendor, .ports]
    }

    private let store: UserDefaults
    private(set) var visible: Set<Column>

    /// Reads stored choices, falling back to `Column.defaults` per column.
    ///
    /// Deliberately does not call `register(defaults:)` and writes nothing on init: an absent key
    /// means "the user never chose", which is what lets a default change reach existing installs
    /// while still respecting someone who deliberately turned a column off.
    init(store: UserDefaults = .standard) {
        self.store = store
        self.visible = Set(Column.allCases.filter { column in
            store.object(forKey: column.storageKey) as? Bool ?? Column.defaults.contains(column)
        })
    }

    func isVisible(_ column: Column) -> Bool { visible.contains(column) }

    func set(_ column: Column, to shown: Bool) {
        if shown { visible.insert(column) } else { visible.remove(column) }
        store.set(shown, forKey: column.storageKey)
    }

    func binding(for column: Column) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isVisible(column) ?? false },
            set: { [weak self] shown in self?.set(column, to: shown) }
        )
    }

    func showAll() {
        for column in Column.allCases { set(column, to: true) }
    }

    func resetToDefaults() {
        for column in Column.allCases { set(column, to: Column.defaults.contains(column)) }
    }
}
