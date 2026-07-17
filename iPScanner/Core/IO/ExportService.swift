import Foundation

enum ExportService {
    struct Row: Codable {
        let ip: String
        let label: String?
        let hostname: String?
        let mac: String?
        let vendor: String?
        let rttMs: Double?
        let ttl: Int?
        let openPorts: [Int]
    }

    static func rows(from hosts: [Host], label: (Host) -> String?) -> [Row] {
        hosts.map { h in
            Row(
                ip: h.ip,
                label: label(h),
                hostname: h.hostname,
                mac: h.mac,
                vendor: h.vendor,
                rttMs: h.rttMs,
                ttl: h.ttl,
                openPorts: h.openPorts
            )
        }
    }

    static func csv(rows: [Row]) -> String {
        var out = "IP,Label,Hostname,MAC,Vendor,RTT (ms),TTL,Open Ports\n"
        for r in rows {
            let rtt = r.rttMs.map { String(format: "%.1f", $0) } ?? ""
            let ttl = r.ttl.map(String.init) ?? ""
            let ports = r.openPorts.map(String.init).joined(separator: ";")
            let cells = [
                escape(r.ip),
                escape(r.label),
                escape(r.hostname),
                escape(r.mac),
                escape(r.vendor),
                rtt,
                ttl,
                escape(ports)
            ]
            out += cells.joined(separator: ",") + "\n"
        }
        return out
    }

    static func json(rows: [Row]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(rows)
    }

    /// Flat `ip:port` lines, one per (host, open port) pair. Skips hosts with no open ports.
    /// Convenient for piping into Nmap, firewall rule generators, or `xargs`.
    static func ipPortList(rows: [Row]) -> String {
        var lines: [String] = []
        for r in rows where !r.openPorts.isEmpty {
            for port in r.openPorts {
                lines.append("\(r.ip):\(port)")
            }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// Human-readable plain-text report. Suitable for tickets, email, Slack snippets.
    static func textReport(rows: [Row], rangeInput: String, scannedTotal: Int, aliveCount: Int) -> String {
        var out = "iPScanner Report\n"
        out += "Generated: \(ExportNaming.reportTimestamp())\n"
        if !rangeInput.isEmpty { out += "Range: \(rangeInput)\n" }
        out += "Scanned: \(scannedTotal)\n"
        out += "Alive: \(aliveCount)\n"
        out += String(repeating: "-", count: 60) + "\n"

        // Column widths derived from data so output stays aligned without truncating.
        let ipWidth      = max(15, rows.map { $0.ip.count }.max() ?? 15)
        let hostWidth    = max(20, rows.map { ($0.hostname ?? "").count }.max() ?? 20)
        let vendorWidth  = max(20, rows.map { ($0.vendor ?? "").count }.max() ?? 20)

        out += pad("IP", to: ipWidth) + "  "
            + pad("Hostname", to: hostWidth) + "  "
            + pad("Vendor", to: vendorWidth) + "  "
            + "Ports\n"
        out += String(repeating: "-", count: 60) + "\n"
        for r in rows {
            let ports = r.openPorts.map(String.init).joined(separator: ", ")
            out += pad(r.ip, to: ipWidth) + "  "
                + pad(r.hostname ?? "—", to: hostWidth) + "  "
                + pad(r.vendor ?? "—", to: vendorWidth) + "  "
                + (ports.isEmpty ? "—" : ports) + "\n"
        }
        return out
    }

    static func defaultFileName(ext: String) -> String {
        ExportNaming.fileName(ext: ext)
    }

    /// Leading characters a spreadsheet treats as the start of a formula. A hostname comes from
    /// the scanned host's own PTR record, so it is attacker-controlled: `=cmd|'/c calc'!A1`
    /// contains no comma or quote and would otherwise reach the sheet verbatim and execute on open.
    private static let formulaTriggers: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    private static func escape(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "" }
        // Neutralize the formula by prefixing an apostrophe, then always quote: the apostrophe
        // itself is only interpreted as a text marker inside a quoted field.
        if let first = v.first, formulaTriggers.contains(first) {
            return quoted("'" + v)
        }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return quoted(v)
        }
        return v
    }

    private static func quoted(_ v: String) -> String {
        "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}
