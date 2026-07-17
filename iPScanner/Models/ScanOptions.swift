import Foundation

/// What a scan actually does, as one value.
///
/// The profile used to expose three loose Bools, which NetworkScanner unpacked and passed down as
/// separate parameters — so adding a phase meant threading another Bool through every layer, and
/// the type never said which combinations were meaningful.
struct ScanOptions: Sendable, Hashable {
    /// Try a TCP handshake on hosts that ignore ICMP.
    var useTCPFallback = true

    /// One UDP-137 query for the Windows computer name and workgroup.
    var includeNetBIOS = true

    /// Browse Bonjour alongside the scan.
    var includeMDNS = true

    /// Ports probed on every *alive* host to identify it. Empty skips the phase entirely.
    var fingerprintPorts: [Int] = []

    /// Ask UPnP devices what they are (unicast M-SEARCH), and SNMP agents for sysDescr.
    ///
    /// Deep only, and each is additionally gated on its port having answered the fingerprint round
    /// — so a Standard scan sends no SSDP and no SNMP at all, and a Deep scan only talks to hosts
    /// that already said they were listening.
    var includeSSDP = false
    var includeSNMP = false

    /// Full port scan with banner fetch after discovery finishes.
    var autoPortScan = false
    var autoBanners = false
}

extension ScanProfile {
    var options: ScanOptions {
        switch self {
        case .quick:
            // Unchanged, and now impossible to slow down by accident: an empty fingerprint list
            // short-circuits the phase rather than relying on a flag somewhere else.
            ScanOptions(
                useTCPFallback: false,
                includeNetBIOS: false,
                includeMDNS: false,
                fingerprintPorts: []
            )
        case .standard:
            ScanOptions(fingerprintPorts: PortScanner.fingerprintPorts)
        case .deep:
            ScanOptions(
                fingerprintPorts: PortScanner.fingerprintPorts,
                includeSSDP: true,
                includeSNMP: true,
                autoPortScan: true,
                autoBanners: true
            )
        }
    }
}
