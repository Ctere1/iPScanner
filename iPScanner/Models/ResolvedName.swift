import Foundation

/// A host's name plus where it came from.
///
/// Reverse DNS is the authoritative source but is empty on most networks — a home or office LAN
/// usually has no PTR records at all, which left the Hostname column showing "—" for every host
/// even when the device was broadcasting its name over Bonjour. The scan already collects those
/// other names; this picks the best one and keeps track of which it was, so a name learned from
/// mDNS is not silently presented as reverse DNS.
struct ResolvedName: Equatable {
    enum Source: String {
        case dns = "DNS"
        case mdns = "mDNS"
        case netbios = "NetBIOS"

        /// Shown next to a name that did not come from reverse DNS.
        var badge: String? { self == .dns ? nil : rawValue }

        var explanation: String {
            switch self {
            case .dns: "Name from a reverse DNS (PTR) record."
            case .mdns: "Name advertised by the device over Bonjour/mDNS — no PTR record exists."
            case .netbios: "NetBIOS computer name from a UDP-137 query — no PTR record exists."
            }
        }
    }

    let value: String
    let source: Source

    /// Best available name, most authoritative first. Returns nil when nothing knows a name.
    static func best(dns: String?, mdns: String?, netbios: String?) -> ResolvedName? {
        if let v = dns?.trimmed, !v.isEmpty { return ResolvedName(value: v, source: .dns) }
        if let v = mdns?.trimmed, !v.isEmpty { return ResolvedName(value: v, source: .mdns) }
        if let v = netbios?.trimmed, !v.isEmpty { return ResolvedName(value: v, source: .netbios) }
        return nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
