import Foundation
import Network

enum PortScanner {
    static let commonPorts: [Int] = [22, 80, 443, 445, 3389, 5900, 8080]
    static let defaultPortsInput = "22, 80, 443, 445, 3389, 5900, 8080"
    static let perHostConcurrency = 64

    static let serviceNames: [Int: String] = [
        20: "ftp-data", 21: "ftp", 22: "ssh", 23: "telnet", 25: "smtp",
        53: "dns", 67: "dhcp", 80: "http", 110: "pop3", 119: "nntp",
        123: "ntp", 137: "netbios-ns", 139: "netbios-ssn", 143: "imap",
        161: "snmp", 389: "ldap", 443: "https", 445: "smb",
        465: "smtps", 514: "syslog", 515: "lpd", 587: "submission",
        631: "ipp", 636: "ldaps", 873: "rsync", 990: "ftps",
        993: "imaps", 995: "pop3s", 1194: "openvpn", 1433: "mssql",
        1521: "oracle", 1723: "pptp", 1812: "radius", 2049: "nfs",
        3128: "proxy", 3306: "mysql", 3389: "rdp", 3690: "svn",
        5000: "synology", 5060: "sip", 5222: "xmpp", 5353: "mdns",
        5432: "postgres", 5672: "amqp", 5900: "vnc", 5985: "winrm",
        6379: "redis", 6443: "k8s", 8000: "http-alt", 8008: "http-alt",
        8080: "http-proxy", 8081: "http-proxy", 8443: "https-alt",
        8888: "http-alt", 9090: "prometheus", 9100: "printer",
        9200: "elasticsearch", 9418: "git", 11211: "memcached",
        27017: "mongodb", 32400: "plex"
    ]

    static func serviceName(for port: Int) -> String? {
        serviceNames[port]
    }

    /// Formats ports as "22 (ssh), 443 (https), 9100 (printer)".
    static func formatList(_ ports: [Int]) -> String {
        ports.map { p in
            if let name = serviceName(for: p) { "\(p) (\(name))" } else { "\(p)" }
        }.joined(separator: ", ")
    }

    /// What to show for a host's ports: `—` never probed · `none` probed, all closed · the list.
    ///
    /// The distinction is the point. `formatList([])` returns "" — correct for a list formatter,
    /// but rendered straight into the table it produced a blank cell that read as broken and could
    /// not tell "we never looked" from "we looked and nothing was open".
    static func displayList(open: [Int], scanned: [Int]) -> String {
        guard !scanned.isEmpty else { return "—" }
        return open.isEmpty ? "none" : formatList(open)
    }

    static func probe(_ ip: String, ports: [Int], timeoutMs: Int = 800) async -> [Int] {
        var open: [Int] = []
        await withWindowedTaskGroup(
            over: ports,
            limit: perHostConcurrency,
            operation: { port in (port, await probeOne(ip: ip, port: port, timeoutMs: timeoutMs)) }
        ) { port, isOpen in
            if isOpen { open.append(port) }
            return true
        }
        return open.sorted()
    }

    private static func probeOne(ip: String, port: Int, timeoutMs: Int) async -> Bool {
        guard (1...65535).contains(port) else { return false }
        return await NWProbe.canConnect(ip, port: UInt16(port), timeoutMs: timeoutMs)
    }

    /// Parses "22, 80, 443, 8000-8100" → sorted unique ports. Returns nil on invalid input.
    static func parsePorts(_ input: String) -> [Int]? {
        var result = Set<Int>()
        for chunk in input.split(separator: ",") {
            let part = chunk.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if let dashIdx = part.firstIndex(of: "-") {
                let lo = part[..<dashIdx].trimmingCharacters(in: .whitespaces)
                let hi = part[part.index(after: dashIdx)...].trimmingCharacters(in: .whitespaces)
                guard let l = Int(lo), let h = Int(hi),
                      (1...65535).contains(l), (1...65535).contains(h),
                      l <= h else { return nil }
                result.formUnion(l...h)
            } else {
                guard let p = Int(part), (1...65535).contains(p) else { return nil }
                result.insert(p)
            }
        }
        return result.isEmpty ? nil : result.sorted()
    }
}
