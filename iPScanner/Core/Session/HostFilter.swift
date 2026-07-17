import Foundation

/// Which rows the table shows, and in what order.
///
/// Pure: takes the hosts, returns the visible ones. It lived on the controller as a computed
/// property, which is what made it untestable — and is why the device-type filter's `classify`
/// call ran on every SwiftUI render rather than once per host.
struct HostFilter: Equatable, Sendable {
    var showDead = false
    var hasOpenPorts = false
    var hasLabel = false
    var hasVendor = false
    var identifiedDevice = false
    var query = ""

    /// Whether any *scope* filter is on. `showDead` and `query` are deliberately excluded: they
    /// have their own controls, and the "clear filters" affordance must not silently reset them.
    var hasActiveScopeFilters: Bool {
        hasOpenPorts || hasLabel || hasVendor || identifiedDevice
    }

    mutating func clearScopeFilters() {
        hasOpenPorts = false
        hasLabel = false
        hasVendor = false
        identifiedDevice = false
    }

    /// - Parameter label: resolves a host's user label; the store that owns them is not this type's
    ///   business.
    func apply(
        to hosts: [Host],
        label: (Host) -> String?,
        sortOrder: [KeyPathComparator<Host>]
    ) -> [Host] {
        var visible = showDead ? hosts : hosts.filter { $0.status != .dead }
        if hasOpenPorts {
            visible = visible.filter { !$0.openPorts.isEmpty }
        }
        if hasLabel {
            visible = visible.filter { label($0) != nil }
        }
        if hasVendor {
            visible = visible.filter { $0.vendor?.isEmpty == false }
        }
        if identifiedDevice {
            visible = visible.filter { DeviceClassifier.classify($0) != .unknown }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            visible = visible.filter { host in
                host.ip.lowercased().contains(q)
                    || (host.hostname?.lowercased().contains(q) ?? false)
                    || (host.mac?.lowercased().contains(q) ?? false)
                    || (host.vendor?.lowercased().contains(q) ?? false)
                    || (host.serviceTitle?.lowercased().contains(q) ?? false)
                    || (label(host)?.lowercased().contains(q) ?? false)
            }
        }
        return visible.sorted(using: sortOrder)
    }
}
