import Foundation

protocol NetworkScanning: Sendable {
    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent>
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

struct NetworkScanner: NetworkScanning {
    static let pingConcurrency = 32
    static let enrichConcurrency = 16
    static let pingTimeoutMs = 800
    static let tcpFallbackPorts = [445, 80, 443, 22, 3389]
    static let tcpFallbackTimeoutMs = 400

    let profile: ScanProfile

    init(profile: ScanProfile = .standard) {
        self.profile = profile
    }

    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent> {
        scan(addresses: range.addresses)
    }

    func scan(addresses: [String]) -> AsyncStream<ScanEvent> {
        let useTCPFallback = profile.useTCPFallback
        let includeNetBIOS = profile.includeNetBIOS
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.run(
                    addresses: addresses,
                    useTCPFallback: useTCPFallback,
                    includeNetBIOS: includeNetBIOS,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func run(
        addresses: [String],
        useTCPFallback: Bool,
        includeNetBIOS: Bool = false,
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
            operation: { ip in (ip, await Self.discover(ip, useTCPFallback: useTCPFallback)) }
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
        try? await Task.sleep(for: .milliseconds(200))
        let arpTable = await ARPLookup.table()
        if arpTable.isEmpty, !alive.isEmpty {
            continuation.yield(.warning(.arpEmpty))
        }
        let oui = OUILookup.shared

        // --- Phase 2: enrich (DNS + MAC + Vendor) per alive host ---
        await withWindowedTaskGroup(
            over: alive,
            limit: Self.enrichConcurrency,
            operation: { entry in
                let mac = arpTable[entry.ip]
                let vendor = mac.flatMap { oui.vendor(forMAC: $0) }
                async let hostname = DNSResolver.reverseLookup(entry.ip)
                async let netbios: NetBIOSResolver.Result? =
                    includeNetBIOS ? NetBIOSResolver.resolve(entry.ip) : nil
                let resolvedHost = await hostname
                let nb = await netbios
                return Host(
                    ip: entry.ip,
                    hostname: resolvedHost,
                    mac: mac,
                    vendor: vendor,
                    rttMs: entry.rtt,
                    ttl: entry.ttl,
                    netbiosName: nb?.computerName,
                    workgroup: nb?.workgroup,
                    openPorts: entry.open,
                    scannedPorts: entry.probed,
                    status: .alive
                )
            }
        ) { host in
            continuation.yield(.host(host))
            return true
        }

        continuation.yield(.done)
        continuation.finish()
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
