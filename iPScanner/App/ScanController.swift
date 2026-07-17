import Foundation
import Observation

@Observable
@MainActor
final class ScanController {
    enum State: Equatable {
        case idle
        case scanning(scanned: Int, total: Int)
        case done(scanned: Int, total: Int)
    }

    static let portScanHostConcurrency = 4
    static let refreshConcurrency = 8

    struct ImportedTargets {
        let url: URL
        let targets: [String]
        let invalidLineCount: Int
    }

    var rangeInput: String = ""
    var searchQuery: String = ""
    var profile: ScanProfile = .standard
    private(set) var importedTargets: ImportedTargets?
    var rescanInterval: RescanInterval = .off {
        didSet { handleRescanIntervalChange() }
    }
    var selection: Set<Host.ID> = []
    var sortOrder: [KeyPathComparator<Host>] = [
        KeyPathComparator(\Host.ipNumeric, order: .forward)
    ]
    let labelStore: LabelStore
    let savedRangeStore: SavedRangeStore

    /// anchor → label (anchor = MAC ?? IP). Reads through to `labelStore`, which owns persistence.
    var labels: [String: String] { labelStore.labels }
    var savedRanges: [SavedRange] { savedRangeStore.ranges }

    var showDeadHosts: Bool = false
    var filterHasOpenPorts: Bool = false
    var filterHasLabel: Bool = false
    var filterHasVendor: Bool = false
    var filterIdentifiedDevice: Bool = false

    var hasActiveScopeFilters: Bool {
        filterHasOpenPorts || filterHasLabel || filterHasVendor || filterIdentifiedDevice
    }

    func clearScopeFilters() {
        filterHasOpenPorts = false
        filterHasLabel = false
        filterHasVendor = false
        filterIdentifiedDevice = false
    }

    private(set) var hosts: [Host] = []
    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var portScanInProgress: Bool = false
    private(set) var portScanProgress: (scanned: Int, total: Int) = (0, 0)
    private(set) var warnings: [ScanWarning] = []
    private(set) var diff: SnapshotDiff?
    private var diffBaseline: ScanSnapshot?
    private var portScanTask: Task<Void, Never>?
    /// Bumped on every start and cancel. A run whose generation is stale has been superseded and
    /// must not write results or clear the current run's progress flags.
    private var portScanGeneration: UInt64 = 0

    /// Stores are injected so a test can construct a controller without touching the real app's
    /// saved labels and ranges — the previous init read `UserDefaults.standard` unconditionally.
    init(
        labelStore: LabelStore? = nil,
        savedRangeStore: SavedRangeStore? = nil
    ) {
        // Built here rather than as default arguments: a default argument is evaluated in the
        // caller's isolation, and these are @MainActor.
        self.labelStore = labelStore ?? LabelStore()
        self.savedRangeStore = savedRangeStore ?? SavedRangeStore()
    }

    /// IP → position in `hosts`. Enrichment merges one event per host per phase, so resolving the
    /// row by index keeps that path O(1); a `firstIndex(where:)` scan makes it O(n) per event.
    /// Must be rebuilt whenever `hosts` is reordered or has elements removed.
    private var indexByIp: [String: Int] = [:]
    private var scanTask: Task<Void, Never>?
    private var startDate: Date?
    private var elapsedTimer: Timer?
    private var rescanTimer: Timer?
    private(set) var nextRescanAt: Date?

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var aliveCount: Int { hosts.filter { $0.status == .alive }.count }

    // MARK: - Host index

    private func rebuildIndex() {
        indexByIp = Dictionary(
            hosts.enumerated().map { ($0.element.ip, $0.offset) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Position of `id` in `hosts`, or nil if it is gone. The id check guards against writing to a
    /// different host that has since taken the same IP (restore, delete, re-add).
    private func index(of id: Host.ID, ip: String) -> Int? {
        guard let idx = indexByIp[ip], hosts.indices.contains(idx), hosts[idx].id == id else {
            return nil
        }
        return idx
    }

    var filteredHosts: [Host] {
        var visible = showDeadHosts ? hosts : hosts.filter { $0.status != .dead }
        if filterHasOpenPorts {
            visible = visible.filter { !$0.openPorts.isEmpty }
        }
        if filterHasLabel {
            visible = visible.filter { label(for: $0) != nil }
        }
        if filterHasVendor {
            visible = visible.filter { ($0.vendor?.isEmpty == false) }
        }
        if filterIdentifiedDevice {
            visible = visible.filter { DeviceClassifier.classify($0) != .unknown }
        }
        let rows: [Host]
        if searchQuery.isEmpty {
            rows = visible
        } else {
            let q = searchQuery.lowercased()
            rows = visible.filter { h in
                h.ip.lowercased().contains(q)
                    || (h.hostname?.lowercased().contains(q) ?? false)
                    || (h.mac?.lowercased().contains(q) ?? false)
                    || (h.vendor?.lowercased().contains(q) ?? false)
                    || (h.serviceTitle?.lowercased().contains(q) ?? false)
                    || (label(for: h)?.lowercased().contains(q) ?? false)
            }
        }
        return rows.sorted(using: sortOrder)
    }

    // MARK: - Labels

    func anchor(for host: Host) -> String { labelStore.anchor(for: host) }

    func label(for host: Host) -> String? { labelStore.label(for: host) }

    func setLabel(_ value: String?, for host: Host) { labelStore.setLabel(value, for: host) }

    func setLabel(_ value: String?, forAnchor key: String) {
        labelStore.setLabel(value, forAnchor: key)
    }

    // MARK: - Saved ranges

    var isCurrentRangeSaved: Bool { savedRangeStore.isSaved(rangeInput) }

    func toggleSaveCurrentRange() { savedRangeStore.toggle(rangeInput) }

    func removeSavedRange(_ range: String) { savedRangeStore.remove(range) }

    func renameSavedRange(_ range: String, to name: String?) {
        savedRangeStore.rename(range, to: name)
    }

    func loadSavedRange(_ range: String) {
        rangeInput = range
    }

    func detectDefaultSubnetIfNeeded() {
        guard rangeInput.isEmpty, importedTargets == nil else { return }
        if let subnet = NetworkInterface.defaultSubnet() {
            rangeInput = subnet
        }
    }

    // MARK: - Imported targets (file)

    /// Result of attempting to load a target list file. Surfaced on the controller so the UI can render warnings.
    struct ImportSummary {
        let targetCount: Int
        let invalidLineCount: Int
    }

    @discardableResult
    func loadImportedFile(url: URL) throws -> ImportSummary {
        let result = try TargetFileParser.parse(url: url)
        if result.targets.isEmpty {
            throw TargetFileParser.ParseError.noTargets
        }
        importedTargets = ImportedTargets(
            url: url,
            targets: result.targets,
            invalidLineCount: result.invalidLines.count
        )
        lastError = nil
        return ImportSummary(
            targetCount: result.targets.count,
            invalidLineCount: result.invalidLines.count
        )
    }

    func clearImportedFile() {
        importedTargets = nil
    }

    func start() {
        guard !isScanning else { return }

        let addresses: [String]
        if let imported = importedTargets {
            addresses = imported.targets
        } else {
            let parsed = ScanRange.parseAll(rangeInput)
            if let badIdx = parsed.firstInvalidIndex {
                lastError = "Invalid range (chunk \(badIdx)). E.g. 10.0.0.0/24, 192.168.1.0/24, 172.16.5.50-172.16.5.100"
                return
            }
            guard !parsed.ranges.isEmpty else {
                lastError = "Enter an IP range (e.g. 10.0.0.0/24)."
                return
            }
            // Rejects oversized input before expansion; `imported.targets` is capped by TargetFileParser.
            guard let expanded = ScanRange.uniqueAddresses(parsed.ranges) else {
                let span = ScanRange.totalHostCount(parsed.ranges)
                lastError = "Total target list too large (\(span) addresses, limit \(ScanRange.maxTargets)). Narrow the range."
                return
            }
            addresses = expanded
        }

        guard !addresses.isEmpty else {
            lastError = "No targets to scan."
            return
        }

        lastError = nil
        // A deep-profile port scan from the previous run would otherwise keep writing into the
        // host list this line clears, and keep `portScanInProgress` set against the new run.
        cancelPortScan()
        hosts = []
        indexByIp = [:]
        warnings = []
        cancelRescanTimer()
        startDate = Date()
        elapsed = 0
        state = .scanning(scanned: 0, total: addresses.count)

        elapsedTimer?.invalidate()
        // Elapsed renders to one decimal, so a 0.25s period looks identical to 0.1s while cutting
        // wakeups by 60%; the tolerance lets the timer coalesce with other work instead of forcing
        // its own wakeup. Each tick invalidates observers, so the cost is more than the timer itself.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        timer.tolerance = 0.1
        elapsedTimer = timer

        let scanner = NetworkScanner(profile: profile)
        let runProfile = profile
        scanTask = Task { [weak self] in
            for await event in scanner.scan(addresses: addresses) {
                guard let self else { return }
                self.handle(event: event)
                if Task.isCancelled { break }
            }
            // Deep profile: chain a common-port scan with banner fetch on alive hosts.
            if !Task.isCancelled, runProfile.autoPortScan {
                guard let self else { return }
                await MainActor.run {
                    let aliveIDs = Set(self.hosts.filter { $0.status == .alive }.map { $0.id })
                    guard !aliveIDs.isEmpty,
                          let ports = PortScanner.parsePorts(PortScanner.defaultPortsInput) else { return }
                    self.runPortScan(ports: ports, fetchBanners: true, targetIds: aliveIDs)
                }
            }
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        // A deep-profile scan chains an auto port scan; without this it survives Stop.
        cancelPortScan()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        cancelRescanTimer()
        if case .scanning(let s, let t) = state {
            state = .done(scanned: s, total: t)
        }
    }

    private func handleRescanIntervalChange() {
        cancelRescanTimer()
        // If the previous scan already finished and an interval is now set, prime the next tick.
        if case .done = state, rescanInterval.seconds != nil {
            scheduleRescan()
        }
    }

    private func scheduleRescan() {
        guard let interval = rescanInterval.seconds else { return }
        cancelRescanTimer()
        nextRescanAt = Date().addingTimeInterval(interval)
        rescanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rescanTimer = nil
                self.nextRescanAt = nil
                if !self.isScanning, !self.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.start()
                }
            }
        }
    }

    private func cancelRescanTimer() {
        rescanTimer?.invalidate()
        rescanTimer = nil
        nextRescanAt = nil
    }

    func runPortScan(ports: [Int], fetchBanners: Bool = false, targetIds: Set<Host.ID>? = nil) {
        let ids = targetIds ?? selection
        let targets = hosts.filter { ids.contains($0.id) }
        guard !targets.isEmpty, !portScanInProgress else { return }
        portScanInProgress = true
        portScanProgress = (0, targets.count)

        portScanGeneration &+= 1
        let generation = portScanGeneration
        portScanTask = Task { [weak self] in
            await self?.executePortScan(
                targets: targets, ports: ports, fetchBanners: fetchBanners, generation: generation
            )
            await MainActor.run { [weak self] in
                // A cancelled run must not clear the flags of the run that replaced it.
                guard let self, self.portScanGeneration == generation else { return }
                self.portScanInProgress = false
                self.portScanTask = nil
            }
        }
    }

    func cancelPortScan() {
        portScanTask?.cancel()
        portScanTask = nil
        portScanInProgress = false
        // Retires the in-flight run: its writebacks and completion block become no-ops.
        portScanGeneration &+= 1
    }

    private func executePortScan(
        targets: [Host], ports: [Int], fetchBanners: Bool, generation: UInt64
    ) async {
        var completed = 0

        await withTaskGroup(of: (Host.ID, String, [Int]).self) { group in
            var iter = targets.makeIterator()
            for _ in 0..<min(Self.portScanHostConcurrency, targets.count) {
                guard let host = iter.next() else { break }
                let ip = host.ip
                let id = host.id
                group.addTask { (id, ip, await PortScanner.probe(ip, ports: ports)) }
            }
            while let (id, ip, openPorts) = await group.next() {
                if Task.isCancelled || generation != self.portScanGeneration {
                    group.cancelAll()
                    break
                }
                if let idx = self.index(of: id, ip: ip) {
                    self.hosts[idx].mergePortResults(probed: ports, open: openPorts)
                }
                completed += 1
                self.portScanProgress = (completed, targets.count)
                if let next = iter.next() {
                    let nextIP = next.ip
                    let nextId = next.id
                    group.addTask { (nextId, nextIP, await PortScanner.probe(nextIP, ports: ports)) }
                }
            }
        }

        if Task.isCancelled || generation != portScanGeneration { return }
        guard fetchBanners else { return }

        // Banners follow the hosts this run actually port-scanned. Deriving them from `selection`
        // instead fetched nothing during an auto deep scan (selection is empty then) and could
        // target hosts that were never scanned.
        let bannerTargets: [(Host.ID, String, [Int])] = targets.compactMap { t in
            guard let idx = index(of: t.id, ip: t.ip) else { return nil }
            let banner = hosts[idx].openPorts.filter { BannerProbe.bannerPorts.contains($0) }
            return banner.isEmpty ? nil : (t.id, t.ip, banner)
        }

        var failures = 0
        await withTaskGroup(of: (Host.ID, String, String?).self) { group in
            for (id, ip, ports) in bannerTargets {
                group.addTask { (id, ip, await BannerProbe.fetch(ip, openPorts: ports)) }
            }
            for await (id, ip, title) in group {
                if Task.isCancelled || generation != self.portScanGeneration {
                    group.cancelAll()
                    break
                }
                guard let title else { failures += 1; continue }
                if let idx = self.index(of: id, ip: ip) {
                    self.hosts[idx].serviceTitle = title
                }
            }
        }
        if failures > 0 {
            mergeWarning(.bannerFetchFailures(count: failures))
        }
    }

    // MARK: - Snapshot

    func makeSnapshot() -> ScanSnapshot {
        let records = hosts.map { h in
            ScanSnapshot.HostRecord(
                ip: h.ip,
                hostname: h.hostname,
                mac: h.mac,
                vendor: h.vendor,
                rttMs: h.rttMs,
                ttl: h.ttl,
                netbiosName: h.netbiosName,
                workgroup: h.workgroup,
                openPorts: h.openPorts,
                scannedPorts: h.scannedPorts,
                serviceTitle: h.serviceTitle
            )
        }
        var relevantLabels: [String: String] = [:]
        for h in hosts {
            let key = anchor(for: h)
            if let label = labels[key] {
                relevantLabels[key] = label
            }
        }
        return ScanSnapshot(
            version: ScanSnapshot.currentVersion,
            createdAt: Date(),
            rangeInput: rangeInput,
            hosts: records,
            labels: relevantLabels
        )
    }

    func reportError(_ message: String?) {
        lastError = message
    }

    /// A failure the user needs to see now, as opposed to `lastError`.
    ///
    /// `lastError` is rendered inline in the empty state, which only exists while there are no
    /// hosts — right for "Enter an IP range", useless for anything else. Export and snapshot
    /// failures can only happen once hosts exist, so every one of them was written to a property
    /// nothing on screen was reading: the save silently did nothing and looked like it worked.
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private(set) var alert: AlertMessage?

    func report(title: String, message: String) {
        alert = AlertMessage(title: title, message: message)
    }

    func dismissAlert() {
        alert = nil
    }

    // MARK: - Comparison / diff

    func loadComparisonBaseline(_ snapshot: ScanSnapshot) {
        diffBaseline = snapshot
        recomputeDiff()
    }

    func clearComparison() {
        diffBaseline = nil
        diff = nil
    }

    func recomputeDiff() {
        guard let baseline = diffBaseline else { diff = nil; return }
        diff = SnapshotDiff.compute(current: hosts, baseline: baseline)
    }

    func change(for host: Host) -> HostChange? {
        diff?.changesByAnchor[host.mac ?? host.ip]
    }

    func applySnapshot(_ snapshot: ScanSnapshot) {
        stop()
        scanTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        importedTargets = nil
        rangeInput = snapshot.rangeInput
        let restored = snapshot.hosts.map { rec in
            Host(
                ip: rec.ip,
                hostname: rec.hostname,
                mac: rec.mac,
                vendor: rec.vendor,
                rttMs: rec.rttMs,
                ttl: rec.ttl,
                netbiosName: rec.netbiosName,
                workgroup: rec.workgroup,
                openPorts: rec.openPorts,
                scannedPorts: rec.scannedPorts,
                serviceTitle: rec.serviceTitle,
                status: .alive
            )
        }
        hosts = restored
        // A snapshot file is user-supplied and may repeat an IP; last one wins rather than trapping.
        rebuildIndex()
        labelStore.merge(snapshot.labels)
        selection = []
        elapsed = 0
        startDate = nil
        warnings = []
        state = .done(scanned: restored.count, total: restored.count)
        lastError = nil
    }

    func deleteHosts(_ ids: Set<Host.ID>) {
        guard !ids.isEmpty else { return }
        hosts.removeAll { ids.contains($0.id) }
        // Removal shifts every later element, so the whole index is rebuilt, not just the gaps.
        rebuildIndex()
        selection.subtract(ids)
    }

    /// Refreshes several hosts through a bounded window with one shared ARP table. An unbounded
    /// group spawned a `/sbin/ping` and a `/usr/sbin/arp` process per host, so "select all →
    /// refresh" on a /24 meant ~500 concurrent processes, each blocking a dispatch thread.
    func refreshHosts(_ ids: Set<Host.ID>) async {
        let targets = hosts.filter { ids.contains($0.id) }.map(\.id)
        guard !targets.isEmpty else { return }
        let arpTable = await ARPLookup.table()

        await withTaskGroup(of: Void.self) { group in
            var iter = targets.makeIterator()
            for _ in 0..<min(Self.refreshConcurrency, targets.count) {
                guard let id = iter.next() else { break }
                group.addTask { await self.refreshHost(id, sharedARPTable: arpTable) }
            }
            while await group.next() != nil {
                guard let next = iter.next() else { continue }
                group.addTask { await self.refreshHost(next, sharedARPTable: arpTable) }
            }
        }
    }

    func refreshHost(_ id: Host.ID, sharedARPTable: [String: String]? = nil) async {
        guard let target = hosts.first(where: { $0.id == id }) else { return }
        let ip = target.ip
        if let idx = index(of: id, ip: ip) {
            hosts[idx].status = .scanning
        }

        let result = await NetworkScanner.discover(ip)
        guard let idx = index(of: id, ip: ip) else { return }

        guard let result = result else {
            hosts[idx].status = .dead
            hosts[idx].rttMs = nil
            hosts[idx].ttl = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(200))
        // Callers refreshing several hosts pass one shared table; each `table()` call is its own
        // `/usr/sbin/arp` process, so a bulk refresh would otherwise spawn one per host.
        let arpTable: [String: String]
        if let sharedARPTable {
            arpTable = sharedARPTable
        } else {
            arpTable = await ARPLookup.table()
        }
        async let hostnameTask = DNSResolver.reverseLookup(ip)
        async let netbiosTask: NetBIOSResolver.Result? =
            profile.includeNetBIOS ? NetBIOSResolver.resolve(ip) : nil
        let hostname = await hostnameTask
        let netbios = await netbiosTask
        let mac = arpTable[ip]
        let vendor = mac.flatMap { OUILookup.shared.vendor(forMAC: $0) }

        guard let idx2 = index(of: id, ip: ip) else { return }
        hosts[idx2].status = .alive
        hosts[idx2].rttMs = result.rttMs
        hosts[idx2].ttl = result.ttl
        if let h = hostname { hosts[idx2].hostname = h }
        if let m = mac { hosts[idx2].mac = m }
        if let v = vendor { hosts[idx2].vendor = v }
        if let n = netbios?.computerName { hosts[idx2].netbiosName = n }
        if let w = netbios?.workgroup { hosts[idx2].workgroup = w }
    }

    func runWakeOnLAN(for ids: Set<Host.ID>) async {
        let macs = hosts
            .filter { ids.contains($0.id) }
            .compactMap { $0.mac }
        guard !macs.isEmpty else { return }
        await WakeOnLAN.wakeAll(macs: macs)
    }

    private func mergeWarning(_ w: ScanWarning) {
        switch w {
        case .arpEmpty:
            if !warnings.contains(where: { if case .arpEmpty = $0 { return true } else { return false } }) {
                warnings.append(w)
            }
        case .bannerFetchFailures(let count):
            if let idx = warnings.firstIndex(where: {
                if case .bannerFetchFailures = $0 { return true } else { return false }
            }), case .bannerFetchFailures(let existing) = warnings[idx] {
                warnings[idx] = .bannerFetchFailures(count: existing + count)
            } else {
                warnings.append(.bannerFetchFailures(count: count))
            }
        }
    }

    private func handle(event: ScanEvent) {
        switch event {
        case .progress(let scanned, let total):
            state = .scanning(scanned: scanned, total: total)
        case .warning(let w):
            mergeWarning(w)
        case .host(let h):
            if let idx = indexByIp[h.ip], hosts.indices.contains(idx) {
                hosts[idx].merge(h)
            } else {
                indexByIp[h.ip] = hosts.count
                hosts.append(h)
            }
        case .done:
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            if case .scanning(let s, let t) = state {
                state = .done(scanned: s, total: t)
            } else {
                state = .done(scanned: hosts.count, total: hosts.count)
            }
            recomputeDiff()
            scheduleRescan()
        }
    }
}
