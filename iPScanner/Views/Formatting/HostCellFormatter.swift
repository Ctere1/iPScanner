import SwiftUI

/// Formats host fields for the table's cells.
///
/// The RTT and TTL columns share one cell whose content depends on which of the two are visible,
/// so the formatting has to know about column visibility — but nothing else about the view.
enum HostCellFormatter {
    static func rttTtlHeader(showRTT: Bool, showTTL: Bool) -> String {
        switch (showRTT, showTTL) {
        case (true, true): "RTT / TTL"
        case (true, false): "RTT"
        case (false, true): "TTL"
        case (false, false): ""
        }
    }

    static func rttTtlCell(_ host: Host, showRTT: Bool, showTTL: Bool) -> String {
        var parts: [String] = []
        if showRTT {
            parts.append(host.rttMs.map { String(format: "%.1f ms", $0) } ?? "—")
        }
        if showTTL {
            parts.append(host.ttl.map { "ttl \($0)" } ?? "—")
        }
        return parts.joined(separator: " · ")
    }

    /// Explains where a host's port list came from, which is not obvious: an empty list can mean
    /// nobody looked, and a short one can mean discovery happened to try five ports.
    static func portsHelp(for host: Host) -> String {
        if host.scannedPorts.isEmpty {
            return "Not port-scanned. Select the host and run Port Scan."
        }
        if Set(host.scannedPorts) == Set(NetworkScanner.tcpFallbackPorts) {
            let tried = PortScanner.formatList(NetworkScanner.tcpFallbackPorts.sorted())
            return "Found during host discovery, which tried \(tried). Run Port Scan for a full list."
        }
        let n = host.scannedPorts.count
        return "Scanned \(n) port\(n == 1 ? "" : "s")."
    }

    /// Renders text with `query` highlighted. Falls through to plain text when the query is empty
    /// or does not match.
    static func highlighted(_ source: String, query: String) -> AttributedString {
        var attr = AttributedString(source)
        guard !query.isEmpty,
              let range = attr.range(of: query, options: [.caseInsensitive]) else {
            return attr
        }
        attr[range].backgroundColor = .yellow.opacity(0.4)
        return attr
    }

    /// Rough heuristic translating an ICMP TTL into a probable origin OS.
    /// Real values vary; this is a hint only.
    static func ttlHint(for ttl: Int?) -> String {
        guard let ttl else { return "" }
        if ttl >= 250 { return "TTL \(ttl) — likely Cisco / network device" }
        if ttl >= 120 { return "TTL \(ttl) — likely Windows" }
        if ttl >= 60  { return "TTL \(ttl) — likely Linux / macOS / BSD" }
        return "TTL \(ttl)"
    }
}
