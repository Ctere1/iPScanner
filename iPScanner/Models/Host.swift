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
    /// Ports actually probed on this host.
    ///
    /// Distinguishes "never looked" from "looked, nothing was open" — `openPorts.isEmpty` alone
    /// cannot tell those apart, which is why the Ports column rendered an identical blank cell for
    /// a host that had been scanned and one that never had.
    var scannedPorts: [Int]
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
        scannedPorts: [Int] = [],
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
        self.scannedPorts = scannedPorts
        self.serviceTitle = serviceTitle
        self.status = status
    }

    // MARK: - Sort keys
    //
    // `TableColumn(_:value:)` needs a non-optional Comparable key, and without one a column's
    // header is inert — only IP was sortable, so clicking any other header did nothing, which
    // reads as broken rather than unsupported.

    var hostnameSort: String { hostname ?? "" }
    var macSort: String { mac ?? "" }
    var vendorSort: String { vendor ?? "" }
    var titleSort: String { serviceTitle ?? "" }
    /// Unknown sorts last ascending rather than pretending to be 0 ms.
    var rttSort: Double { rttMs ?? .greatestFiniteMagnitude }
    var ttlSort: Int { ttl ?? .max }
    var openPortCount: Int { openPorts.count }

    /// Folds the result of probing `probed` into what is already known.
    ///
    /// Re-probing a port replaces its verdict; a port that was not probed keeps the one it had.
    /// Plain assignment could not express either: scanning just 8080 would erase the 445 that host
    /// discovery had already found, and an empty result was indistinguishable from "not scanned".
    mutating func mergePortResults(probed: [Int], open: [Int]) {
        let probedSet = Set(probed)
        openPorts = (openPorts.filter { !probedSet.contains($0) } + open).sorted()
        scannedPorts = Array(Set(scannedPorts).union(probedSet)).sorted()
    }
}
