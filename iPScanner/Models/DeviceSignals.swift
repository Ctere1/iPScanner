import Foundation

/// Everything known about a host that might say what it is.
///
/// The classifier used to take a `Host`, so it could only ever see what `Host` stores — which is
/// why mDNS, sitting in a view's state, was invisible to it no matter how much it knew. Widening
/// the input type is what lets evidence reach the rules at all.
struct DeviceSignals: Hashable, Sendable {
    var ip: String = ""
    var mac: String?
    var vendor: String?
    var hostname: String?
    var netbiosName: String?
    var workgroup: String?
    var serviceTitle: String?
    /// SSDP SERVER / UPnP device description / SNMP sysDescr, pooled.
    var probeDescription: String?
    var ttl: Int?
    var openPorts: Set<Int> = []
    var scannedPorts: Set<Int> = []

    /// Bonjour service types seen for this IP, e.g. `_ipp._tcp`.
    var mdnsTypes: Set<String> = []
    /// Merged TXT records across this IP's services, keys lowercased.
    var mdnsTXT: [String: String] = [:]
    /// True when this host is the subnet's default gateway — on a LAN, the strongest single
    /// statement that something is a router.
    var isDefaultGateway = false

    // Derived once at construction; every rule reads these rather than re-splitting strings.
    private(set) var hostnameTokens: Set<String> = []
    /// Vendor, banner title and NetBIOS name pooled and lowercased. Substring matching is safe on
    /// these — unlike a hostname, they are prose, not a compressed identifier.
    private(set) var descriptionText: String = ""

    init(
        ip: String = "",
        mac: String? = nil,
        vendor: String? = nil,
        hostname: String? = nil,
        netbiosName: String? = nil,
        workgroup: String? = nil,
        serviceTitle: String? = nil,
        probeDescription: String? = nil,
        ttl: Int? = nil,
        openPorts: Set<Int> = [],
        scannedPorts: Set<Int> = [],
        mdnsTypes: Set<String> = [],
        mdnsTXT: [String: String] = [:],
        isDefaultGateway: Bool = false
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.netbiosName = netbiosName
        self.workgroup = workgroup
        self.serviceTitle = serviceTitle
        self.probeDescription = probeDescription
        self.ttl = ttl
        self.openPorts = openPorts
        self.scannedPorts = scannedPorts
        self.mdnsTypes = mdnsTypes
        // Normalised here rather than trusted from the caller: TXT keys are conventionally
        // lowercase but nothing enforces it, and the rules look them up by a lowercase name. Doing
        // it at the boundary means the invariant holds however the signals were built.
        self.mdnsTXT = Dictionary(
            mdnsTXT.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        self.isDefaultGateway = isDefaultGateway

        // The NetBIOS name is a hostname too, and often the only one a Windows box offers.
        self.hostnameTokens = Tokenizer.tokens(hostname).union(Tokenizer.tokens(netbiosName))
        self.descriptionText = [vendor, serviceTitle, netbiosName, probeDescription]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }
}

extension DeviceSignals {
    /// The signals a scanned host carries on its own.
    ///
    /// - Parameters:
    ///   - mdns: Bonjour types and TXT for this IP, which `Host` does not store.
    ///   - gateway: the subnet's default gateway, if known.
    static func from(
        host: Host,
        mdnsTypes: Set<String> = [],
        mdnsTXT: [String: String] = [:],
        gateway: String? = nil
    ) -> DeviceSignals {
        DeviceSignals(
            ip: host.ip,
            mac: host.mac,
            vendor: host.vendor,
            hostname: host.hostname,
            netbiosName: host.netbiosName,
            workgroup: host.workgroup,
            serviceTitle: host.serviceTitle,
            probeDescription: host.probeDescription,
            ttl: host.ttl,
            openPorts: Set(host.openPorts),
            scannedPorts: Set(host.scannedPorts),
            mdnsTypes: mdnsTypes,
            mdnsTXT: mdnsTXT,
            isDefaultGateway: gateway != nil && gateway == host.ip
        )
    }
}
