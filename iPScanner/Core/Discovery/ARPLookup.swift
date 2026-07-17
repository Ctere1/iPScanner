import Foundation

enum ARPLookup {
    static func table() async -> [String: String] {
        guard let (_, output) = await Subprocess.text("/usr/sbin/arp", ["-an"]) else { return [:] }
        return parse(output)
    }

    /// Splits `arp -an` output into ip → mac. Separated from the subprocess so it is testable.
    static func parse(_ output: String) -> [String: String] {
        var table: [String: String] = [:]
        for line in output.split(separator: "\n") {
            if line.contains("(incomplete)") { continue }
            guard let match = line.firstMatch(of: #/\(([0-9.]+)\)\s+at\s+([0-9a-fA-F:]+)/#) else { continue }
            table[String(match.1)] = String(match.2).lowercased()
        }
        return table
    }
}
