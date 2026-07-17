import Foundation

/// Sendable is declared here rather than retroactively: every stored property is a value type, so
/// the compiler verifies it, and adding a reference-typed field will be flagged instead of silently
/// accepted the way an `@unchecked` conformance would.
struct Host: Identifiable, Hashable, Sendable {
    enum Status: Hashable {
        case scanning
        case alive
        case dead
    }

    let id: UUID
    let ip: String
    /// Stored, not computed: this is the default sort key, and re-parsing `ip` on every comparison
    /// made sorting the table O(n log n) string splits. `ip` is immutable, so it cannot drift.
    let ipNumeric: UInt32
    var hostname: String?
    var mac: String?
    var vendor: String?
    var rttMs: Double?
    var ttl: Int?
    var netbiosName: String?
    var workgroup: String?
    var openPorts: [Int]
    var serviceTitle: String?
    var status: Status

    init(
        id: UUID = UUID(),
        ip: String,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        rttMs: Double? = nil,
        ttl: Int? = nil,
        netbiosName: String? = nil,
        workgroup: String? = nil,
        openPorts: [Int] = [],
        serviceTitle: String? = nil,
        status: Status = .scanning
    ) {
        self.id = id
        self.ip = ip
        self.ipNumeric = IPv4.uint32(from: ip) ?? 0
        self.hostname = hostname
        self.mac = mac
        self.vendor = vendor
        self.rttMs = rttMs
        self.ttl = ttl
        self.netbiosName = netbiosName
        self.workgroup = workgroup
        self.openPorts = openPorts
        self.serviceTitle = serviceTitle
        self.status = status
    }
}
