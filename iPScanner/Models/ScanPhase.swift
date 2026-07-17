import Foundation

/// Which part of a scan is running.
///
/// A scan is four passes, not one, and only the first knows the total up front. Reporting progress
/// for that pass alone meant the bar reached "254 of 254" and then sat there while the rest ran —
/// and the fingerprint pass made that silent wait the longest part of a scan. The phase is carried
/// so the meter can say what it is still doing.
enum ScanPhase: String, Sendable, Hashable {
    /// Ping, then TCP fallback. The pass that knows the address count.
    case discovering
    /// Reverse DNS, MAC, vendor, NetBIOS — per alive host.
    case identifying
    /// The classification port set — per alive host.
    case fingerprinting
    /// UPnP and SNMP, for the few hosts that answer them.
    case probing

    /// Present continuous, for a status line: "Fingerprinting 12 of 40".
    var label: String {
        switch self {
        case .discovering: "Scanning"
        case .identifying: "Identifying"
        case .fingerprinting: "Fingerprinting"
        case .probing: "Querying"
        }
    }
}
