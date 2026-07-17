import Foundation

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
