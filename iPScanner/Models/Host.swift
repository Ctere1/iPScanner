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
    /// What SSDP/UPnP and SNMP said, pooled into one lowercase string.
    ///
    /// Stored as text rather than a struct per protocol: every rule that reads it does a phrase
    /// match, and the alternative is five more optional fields that only the classifier ever
    /// touches.
    var probeDescription: String?
    var status: Status

    /// What this host is, and how sure we are.
    ///
    /// Stored rather than derived on read. It used to be recomputed at each of three call sites —
    /// one of them inside a computed property SwiftUI re-evaluates on every render, so the whole
    /// rule table ran once per row per frame. It is also not derivable from a `Host` alone: the
    /// Bonjour evidence and the gateway address live outside it, which is why the classifier
    /// takes `DeviceSignals` and the answer is folded back in here.
    var classification: DeviceClassification = .unknown

    var deviceType: DeviceType { classification.type }

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
        probeDescription: String? = nil,
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
        self.probeDescription = probeDescription
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

    /// Folds a later scan phase's findings for this host into what is already known.
    ///
    /// Discovery yields a host as soon as it answers, then enrichment yields it again with a
    /// hostname, a MAC, a vendor. Each event carries only what its phase learned, so a nil means
    /// "this phase didn't look", never "this host has none" — hence field-by-field rather than
    /// assignment.
    ///
    /// The GUI and the CLI each had their own copy of this. They had already drifted: the CLI's
    /// dropped `netbiosName` and `workgroup`, so `ipscanner` collected NetBIOS names over UDP 137
    /// and then silently discarded them.
    mutating func merge(_ update: Host) {
        if let v = update.hostname { hostname = v }
        if let v = update.mac { mac = v }
        if let v = update.vendor { vendor = v }
        if let v = update.rttMs { rttMs = v }
        if let v = update.ttl { ttl = v }
        if let v = update.netbiosName { netbiosName = v }
        if let v = update.workgroup { workgroup = v }
        if let v = update.serviceTitle { serviceTitle = v }
        if let v = update.probeDescription { probeDescription = v }
        if !update.scannedPorts.isEmpty {
            mergePortResults(probed: update.scannedPorts, open: update.openPorts)
        }
        status = update.status
    }

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
