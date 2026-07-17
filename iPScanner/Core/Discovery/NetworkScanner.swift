import Foundation

/// Discovers hosts, streaming what it learns as it learns it.
///
/// Declares `scan(addresses:)` because that is what callers actually call. The protocol this
/// replaces declared only `scan(_ range:)` — a method neither the GUI nor the CLI used — so it
/// described an API nobody had, could not stand in for the scanner in a test, and no one ever held
/// it as an existential. A convenience for the range form is below, where it belongs.
protocol HostDiscovering: Sendable {
    func scan(addresses: [String]) -> AsyncStream<ScanEvent>
}

extension HostDiscovering {
    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent> {
        scan(addresses: range.addresses)
    }
}

struct DiscoverResult: Sendable, Hashable {
    let rttMs: Double
    /// Only populated for ICMP responses. TCP fallback probes don't expose a useful TTL.
    let ttl: Int?
    /// Ports the discovery probe tried, and which of them answered. Empty for the ICMP path — a
    /// host that answered a ping was never port-probed, and claiming otherwise would be a lie.
    var probedPorts: [Int] = []
    var openPorts: [Int] = []
}

struct NetworkScanner: HostDiscovering {
    static let pingConcurrency = 32
    static let enrichConcurrency = 16
    static let pingTimeoutMs = 800
    static let tcpFallbackPorts = [445, 80, 443, 22, 3389]
    static let tcpFallbackTimeoutMs = 400

    let profile: ScanProfile

    init(profile: ScanProfile = .standard) {
        self.profile = profile
    }

    func scan(addresses: [String]) -> AsyncStream<ScanEvent> {
        let options = profile.options
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.run(addresses: addresses, options: options, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func run(
        addresses: [String],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let total = addresses.count
        continuation.yield(.progress(scanned: 0, total: total))

        // --- Phase 1: discover (ping → TCP fallback) with bounded concurrency ---
        // Always yield dead hosts so the UI can filter on demand without re-scanning.
        var alive: [(ip: String, rtt: Double, ttl: Int?, probed: [Int], open: [Int])] = []
        var scanned = 0

        await withWindowedTaskGroup(
            over: addresses,
            limit: Self.pingConcurrency,
            operation: { ip in (ip, await Self.discover(ip, useTCPFallback: options.useTCPFallback)) }
        ) { ip, result in
            scanned += 1
            continuation.yield(.progress(scanned: scanned, total: total))
            if let result = result {
                alive.append((ip, result.rttMs, result.ttl, result.probedPorts, result.openPorts))
                continuation.yield(.host(Host(
                    ip: ip,
                    rttMs: result.rttMs,
                    ttl: result.ttl,
                    openPorts: result.openPorts,
                    scannedPorts: result.probedPorts,
                    status: .alive
                )))
            } else {
                continuation.yield(.host(Host(ip: ip, status: .dead)))
            }
            return true
        }

        if Task.isCancelled {
            continuation.yield(.done)
            continuation.finish()
            return
        }

        // --- ARP grace ---
        try? await Task.sleep(for: .milliseconds(HostEnricher.arpGraceMs))
        let arpTable = await ARPLookup.table()
        if arpTable.isEmpty, !alive.isEmpty {
            continuation.yield(.warning(.arpEmpty))
        }
        let oui = OUILookup.shared

        // --- Phase 2: enrich (DNS + MAC + Vendor) per alive host ---
        var enriched = 0
        await withWindowedTaskGroup(
            over: alive,
            limit: Self.enrichConcurrency,
            operation: { entry in
                let found = await HostEnricher.enrich(
                    ip: entry.ip,
                    arpTable: arpTable,
                    includeNetBIOS: options.includeNetBIOS,
                    vendors: oui
                )
                return Host(
                    ip: entry.ip,
                    hostname: found.hostname,
                    mac: found.mac,
                    vendor: found.vendor,
                    rttMs: entry.rtt,
                    ttl: entry.ttl,
                    netbiosName: found.netbiosName,
                    workgroup: found.workgroup,
                    openPorts: entry.open,
                    scannedPorts: entry.probed,
                    status: .alive
                )
            }
        ) { host in
            enriched += 1
            continuation.yield(.progress(scanned: enriched, total: alive.count, phase: .identifying))
            continuation.yield(.host(host))
            return true
        }

        if Task.isCancelled {
            continuation.yield(.done)
            continuation.finish()
            return
        }

        // --- Phase 3: fingerprint (identify what each alive host is) ---
        //
        // The reason this phase exists: before it, a host that answered a ping was never
        // port-probed at all on the default profile — the TCP fallback only runs when ICMP
        // *fails*. So the classifier saw a vendor and a hostname and nothing else, and most
        // devices came back unidentified. This costs one bounded round per alive host, and only
        // ever runs against hosts already known to be up.
        var fingerprinted: [(ip: String, open: [Int])] = []
        if !options.fingerprintPorts.isEmpty, !alive.isEmpty {
            let ports = options.fingerprintPorts
            await withWindowedTaskGroup(
                over: alive.map(\.ip),
                limit: Self.enrichConcurrency,
                operation: { ip in (ip, await PortScanner.probe(ip, ports: ports)) }
            ) { ip, open in
                fingerprinted.append((ip, open))
                continuation.yield(.progress(
                    scanned: fingerprinted.count, total: alive.count, phase: .fingerprinting
                ))
                continuation.yield(.host(Host(
                    ip: ip,
                    openPorts: open,
                    scannedPorts: ports,
                    status: .alive
                )))
                return true
            }
        }

        if Task.isCancelled {
            continuation.yield(.done)
            continuation.finish()
            return
        }

        // --- Phase 4: ask the devices that advertise themselves ---
        //
        // Gated twice: on the profile, and on the host having actually answered on the port. A
        // Standard scan therefore sends no SSDP and no SNMP, and a Deep scan only talks to hosts
        // that already said they were listening — rather than spraying UDP at a whole subnet.
        let ssdpTargets = options.includeSSDP
            ? fingerprinted.filter { $0.open.contains(Int(SSDPResponse.port)) }.map(\.ip)
            : []
        let snmpTargets = options.includeSNMP
            ? fingerprinted.filter { $0.open.contains(Int(SNMPMessage.port)) }.map(\.ip)
            : []

        if !ssdpTargets.isEmpty || !snmpTargets.isEmpty {
            let targets = Array(Set(ssdpTargets + snmpTargets))
            let ssdpSet = Set(ssdpTargets)
            let snmpSet = Set(snmpTargets)
            var probed = 0
            await withWindowedTaskGroup(
                over: targets,
                limit: Self.enrichConcurrency,
                operation: { ip -> (String, String?) in
                    async let ssdp: (SSDPResult, UPnPDescription?)? =
                        ssdpSet.contains(ip) ? await SSDPProbe.probeAndDescribe(ip) : nil
                    async let snmp: SNMPResult? =
                        snmpSet.contains(ip) ? await SNMPProbe.probe(ip) : nil
                    return (ip, Self.describe(ssdp: await ssdp, snmp: await snmp))
                }
            ) { ip, description in
                probed += 1
                continuation.yield(.progress(scanned: probed, total: targets.count, phase: .probing))
                guard let description else { return true }
                continuation.yield(.host(Host(ip: ip, probeDescription: description, status: .alive)))
                return true
            }
        }

        continuation.yield(.done)
        continuation.finish()
    }

    /// Pools what the two probes said into the one string the rules phrase-match against.
    private static func describe(
        ssdp: (SSDPResult, UPnPDescription?)?,
        snmp: SNMPResult?
    ) -> String? {
        var parts: [String] = []
        if let (result, description) = ssdp {
            parts.append(contentsOf: [result.server, result.searchTarget].compactMap { $0 })
            if let description { parts.append(description.descriptionText) }
        }
        if let snmp {
            parts.append(contentsOf: [snmp.sysDescr, snmp.sysObjectID, snmp.sysName].compactMap { $0 })
        }
        let joined = parts.joined(separator: " ").trimmed
        return joined.isEmpty ? nil : joined
    }

    // MARK: - discover (ping with TCP fallback)

    /// Returns RTT and (when ICMP succeeded) TTL if the host responded.
    static func discover(_ ip: String, useTCPFallback: Bool = true) async -> DiscoverResult? {
        if let pinged = await ping(ip) { return pinged }
        return useTCPFallback ? await tcpFallback(ip) : nil
    }

    /// ICMP ping. nil if the host did not reply.
    ///
    /// Uses an unprivileged ICMP socket, which costs a file descriptor and no thread. `/sbin/ping`
    /// remains as a fallback for the case where the kernel refuses the socket (a sandbox without
    /// the network-client entitlement), since losing host discovery entirely would be worse than
    /// paying for a subprocess.
    static func ping(_ ip: String) async -> DiscoverResult? {
        if ICMPPing.isAvailable {
            return await ICMPPing.ping(ip, timeoutMs: pingTimeoutMs)
        }
        return await pingViaProcess(ip)
    }

    /// Fallback path: one `/sbin/ping` process per host, each parking a dispatch thread in two
    /// blocking calls for up to `pingTimeoutMs`.
    static func pingViaProcess(_ ip: String) async -> DiscoverResult? {
        guard let (status, output) = await Subprocess.text(
            "/sbin/ping", ["-c", "1", "-W", String(pingTimeoutMs), ip]
        ) else { return nil }
        guard status == 0 else { return nil }
        return parsePingOutput(output)
    }

    /// Pulls rtt and TTL out of `ping -c 1` output. Separated from the subprocess so it is testable.
    static func parsePingOutput(_ output: String) -> DiscoverResult? {
        guard let timeMatch = output.firstMatch(of: #/time=([0-9.]+)\s*ms/#),
              let rtt = Double(timeMatch.1) else { return nil }
        let ttl = output.firstMatch(of: #/ttl=([0-9]+)/#).flatMap { Int($0.1) }
        return DiscoverResult(rttMs: rtt, ttl: ttl)
    }

    /// Concurrent TCP probe across fallback ports. Returns probe duration in ms if any port handshakes.
    ///
    /// Carries the ports out with it. They used to be discarded here, so a host discovered *because*
    /// port 445 answered still showed an empty Ports column — the scan already knew and threw it
    /// away. `PortScanner.probe` tries all of `tcpFallbackPorts` concurrently with no early exit,
    /// so reporting them as probed is accurate.
    static func tcpFallback(_ ip: String) async -> DiscoverResult? {
        let start = Date()
        let openPorts = await PortScanner.probe(ip, ports: tcpFallbackPorts, timeoutMs: tcpFallbackTimeoutMs)
        guard !openPorts.isEmpty else { return nil }
        let elapsedMs = max(0, Date().timeIntervalSince(start) * 1000)
        guard elapsedMs.isFinite else { return nil }
        return DiscoverResult(rttMs: elapsedMs, ttl: nil, probedPorts: tcpFallbackPorts, openPorts: openPorts)
    }
}
