import Foundation

/// Turns a bare IP into an identified host: reverse DNS, MAC, vendor, NetBIOS.
///
/// This existed twice. NetworkScanner ran it as its enrichment phase; ScanController.refreshHost
/// had a hand-copied version for the "refresh this row" action, down to a duplicated 200ms sleep
/// with no explanation of the number. They had already begun to drift, and a signal added to one
/// would silently not appear on the other — a host refreshed by hand would show less than the same
/// host after a full scan.
enum HostEnricher {
    /// How long to let the ARP cache settle before reading it.
    ///
    /// A ping populates the ARP entry asynchronously; reading `arp -an` the instant the reply lands
    /// often misses it, and the host renders with no MAC and therefore no vendor. This is the pause
    /// that makes the cache worth reading.
    static let arpGraceMs = 200

    struct Enrichment: Sendable, Equatable {
        var hostname: String?
        var mac: String?
        var vendor: String?
        var netbiosName: String?
        var workgroup: String?
    }

    /// Resolves everything knowable about `ip` from its address plus an ARP table.
    ///
    /// - Parameter arpTable: shared by callers enriching several hosts — each `ARPLookup.table()`
    ///   spawns its own `/usr/sbin/arp`, so a bulk refresh would otherwise start one per host.
    static func enrich(
        ip: String,
        arpTable: [String: String],
        includeNetBIOS: Bool,
        vendors: OUILookup = .shared
    ) async -> Enrichment {
        async let hostnameTask = DNSResolver.reverseLookup(ip)
        async let netbiosTask: NetBIOSResolver.Result? =
            includeNetBIOS ? NetBIOSResolver.resolve(ip) : nil

        let hostname = await hostnameTask
        let netbios = await netbiosTask
        let mac = arpTable[ip]

        return Enrichment(
            hostname: hostname,
            mac: mac,
            vendor: mac.flatMap { vendors.vendor(forMAC: $0) },
            netbiosName: netbios?.computerName,
            workgroup: netbios?.workgroup
        )
    }
}
