import Foundation

enum ScanProfile: String, CaseIterable, Identifiable, Sendable {
    case quick
    case standard
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .deep: "Deep"
        }
    }

    var description: String {
        switch self {
        case .quick:
            "ICMP ping only — fastest, misses ICMP-blocked hosts (e.g. Windows Firewall)."
        case .standard:
            "Ping + TCP fallback + device fingerprint on alive hosts — identifies what it finds."
        case .deep:
            "Standard + full port scan with banner fetch on alive hosts."
        }
    }

    /// The capability flags now live on `options`; these read through so existing call sites keep
    /// working.

    var useTCPFallback: Bool { options.useTCPFallback }

    var autoPortScan: Bool { options.autoPortScan }

    /// Standard / Deep run an extra UDP-137 query to pull NetBIOS computer name and workgroup.
    /// Quick skips it to keep ICMP-only discovery fast.
    var includeNetBIOS: Bool { options.includeNetBIOS }
}
