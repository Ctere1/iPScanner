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

    /// The filter rules live in `HostFilter`; these stay as the names the views bind to.
    var filter = HostFilter()

    var showDeadHosts: Bool {
        get { filter.showDead }
        set { filter.showDead = newValue }
    }
    var filterHasOpenPorts: Bool {
        get { filter.hasOpenPorts }
        set { filter.hasOpenPorts = newValue }
    }
    var filterHasLabel: Bool {
        get { filter.hasLabel }
        set { filter.hasLabel = newValue }
    }
    var filterHasVendor: Bool {
        get { filter.hasVendor }
        set { filter.hasVendor = newValue }
    }
    var filterIdentifiedDevice: Bool {
        get { filter.identifiedDevice }
        set { filter.identifiedDevice = newValue }
    }

    var hasActiveScopeFilters: Bool { filter.hasActiveScopeFilters }

    func clearScopeFilters() { filter.clearScopeFilters() }

    /// Owns the rows and the IP index. A struct held as a stored property, so mutating it still
    /// notifies observers while keeping the index rules testable without a UI.
    private(set) var hostStore = HostStore()

    var hosts: [Host] { hostStore.hosts }

    /// Bonjour. Owned here rather than by the view, which is the change that lets any of it reach
    /// the classifier: as a view's `@State` its results could only ever be displayed, so the
    /// strongest evidence on a LAN — `_device-info._tcp`'s model, `_googlecast._tcp`, `_ipp._tcp` —
    /// was collected and then discarded.
    let mdns = MDNSDiscovery()

    @ObservationIgnored private let classifier: DeviceClassifier

    /// The subnet's default gateway, if known. Being the gateway is strong router evidence.
    @ObservationIgnored private var gatewayIP: String?

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var portScanInProgress: Bool = false
    private(set) var portScanProgress: (scanned: Int, total: Int) = (0, 0)
    private(set) var warnings: [ScanWarning] = []
    private(set) var diff: SnapshotDiff?
    private var diffBaseline: ScanSnapshot?
    private var portScanTask: Task<Void, Never>?
    private var portScanGeneration = RunGeneration()

    /// Stores are injected so a test can construct a controller without touching the real app's
    /// saved labels and ranges — the previous init read `UserDefaults.standard` unconditionally.
    init(
        labelStore: LabelStore? = nil,
        savedRangeStore: SavedRangeStore? = nil,
        scheduler: Scheduling? = nil,
        makeScanner: (@Sendable (ScanProfile) -> any HostDiscovering)? = nil,
        classifier: DeviceClassifier? = nil
    ) {
        // Built here rather than as default arguments: a default argument is evaluated in the
        // caller's isolation, and these are @MainActor.
        let clock = scheduler ?? TimerScheduler()
        self.labelStore = labelStore ?? LabelStore()
        self.savedRangeStore = savedRangeStore ?? SavedRangeStore()
        self.scheduler = clock
        self.rescanScheduler = RescanScheduler(scheduler: clock)
        self.makeScanner = makeScanner ?? { NetworkScanner(profile: $0) }
        self.classifier = classifier ?? .live
    }

    /// Builds the evidence for one host and asks the rule table.
    private func classification(for host: Host) -> DeviceClassification {
        classifier.classify(DeviceSignals.from(
            host: host,
            mdnsTypes: mdns.serviceTypes(for: host.ip),
            mdnsTXT: mdns.txt(for: host.ip),
            gateway: gatewayIP
        ))
    }

    /// Re-runs classification over every row. Called after a mutation rather than on read.
    func reclassifyHosts() {
        hostStore.reclassify { classification(for: $0) }
    }

    @ObservationIgnored private let scheduler: Scheduling

    /// How a scanner is obtained for a run. Injected so a test can drive the controller from a
    /// scripted event stream rather than the network — `start()` used to construct a
    /// `NetworkScanner` inline, which is why none of the scan lifecycle had tests.
    @ObservationIgnored private let makeScanner: @Sendable (ScanProfile) -> any HostDiscovering

    private var scanTask: Task<Void, Never>?
    private var startDate: Date?
    private var elapsedWork: ScheduledWork?

    let rescanScheduler: RescanScheduler

    var nextRescanAt: Date? { rescanScheduler.nextRescanAt }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var aliveCount: Int { hostStore.aliveCount }

    var filteredHosts: [Host] {
        var active = filter
        active.query = searchQuery
        return active.apply(to: hosts, label: label(for:), sortOrder: sortOrder)
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
            switch TargetResolver.resolve(range: rangeInput) {
            case .targets(let expanded):
                addresses = expanded
            case .invalidChunk(let index):
                lastError = "Invalid range (chunk \(index)). E.g. 10.0.0.0/24, 192.168.1.0/24, 172.16.5.50-172.16.5.100"
                return
            case .empty:
                lastError = "Enter an IP range (e.g. 10.0.0.0/24)."
                return
            case .tooLarge(let span, let limit):
                lastError = "Total target list too large (\(span) addresses, limit \(limit)). Narrow the range."
                return
            }
        }

        guard !addresses.isEmpty else {
            lastError = "No targets to scan."
            return
        }

        lastError = nil
        // Resolved per run: the machine can move between networks, and a gateway from the last
        // subnet would name the wrong host on this one.
        gatewayIP = NetworkInterface.defaultGateway()
        // A deep-profile port scan from the previous run would otherwise keep writing into the
        // host list this line clears, and keep `portScanInProgress` set against the new run.
        cancelPortScan()
        hostStore.removeAll()
        warnings = []
        rescanScheduler.cancel()
        startDate = scheduler.now
        elapsed = 0
        state = .scanning(scanned: 0, total: addresses.count)

        elapsedWork?.cancel()
        // Elapsed renders to one decimal, so a 0.25s period looks identical to 0.1s while cutting
        // wakeups by 60%; the tolerance lets the timer coalesce with other work instead of forcing
        // its own wakeup. Each tick invalidates observers, so the cost is more than the timer itself.
        elapsedWork = scheduler.repeating(every: 0.25, tolerance: 0.1) { [weak self] in
            guard let self, let start = self.startDate else { return }
            self.elapsed = self.scheduler.now.timeIntervalSince(start)
        }

        let scanner = makeScanner(profile)
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
        elapsedWork?.cancel()
        elapsedWork = nil
        rescanScheduler.cancel()
        if case .scanning(let s, let t) = state {
            state = .done(scanned: s, total: t)
        }
    }

    private func handleRescanIntervalChange() {
        rescanScheduler.cancel()
        // If the previous scan already finished and an interval is now set, prime the next tick.
        if case .done = state, rescanInterval.seconds != nil {
            scheduleRescan()
        }
    }

    private func scheduleRescan() {
        guard let interval = rescanInterval.seconds else { return }
        rescanScheduler.schedule(after: interval) { [weak self] in
            guard let self else { return }
            if !self.isScanning, !self.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty {
                self.start()
            }
        }
    }

    func runPortScan(ports: [Int], fetchBanners: Bool = false, targetIds: Set<Host.ID>? = nil) {
        let ids = targetIds ?? selection
        let targets = hosts.filter { ids.contains($0.id) }
        guard !targets.isEmpty, !portScanInProgress else { return }
        portScanInProgress = true
        portScanProgress = (0, targets.count)

        let generation = portScanGeneration.begin()
        portScanTask = Task { [weak self] in
            await self?.executePortScan(
                targets: targets, ports: ports, fetchBanners: fetchBanners, generation: generation
            )
            await MainActor.run { [weak self] in
                // A cancelled run must not clear the flags of the run that replaced it.
                guard let self, self.portScanGeneration.isCurrent(generation) else { return }
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
        portScanGeneration.retire()
    }

    private func executePortScan(
        targets: [Host], ports: [Int], fetchBanners: Bool, generation: UInt64
    ) async {
        var completed = 0

        await withWindowedTaskGroup(
            over: targets.map { (id: $0.id, ip: $0.ip) },
            limit: Self.portScanHostConcurrency,
            operation: { target in
                (target.id, target.ip, await PortScanner.probe(target.ip, ports: ports))
            }
        ) { id, ip, openPorts in
            guard self.portScanGeneration.isCurrent(generation) else { return false }
            self.hostStore.update(id: id, ip: ip) {
                $0.mergePortResults(probed: ports, open: openPorts)
            }
            completed += 1
            self.portScanProgress = (completed, targets.count)
            return true
        }

        if Task.isCancelled || !portScanGeneration.isCurrent(generation) { return }
        guard fetchBanners else { return }

        // Banners follow the hosts this run actually port-scanned. Deriving them from `selection`
        // instead fetched nothing during an auto deep scan (selection is empty then) and could
        // target hosts that were never scanned.
        let bannerTargets: [(Host.ID, String, [Int])] = targets.compactMap { t in
            guard let idx = hostStore.index(of: t.id, ip: t.ip) else { return nil }
            let banner = hosts[idx].openPorts.filter { BannerProbe.bannerPorts.contains($0) }
            return banner.isEmpty ? nil : (t.id, t.ip, banner)
        }

        var failures = 0
        await withWindowedTaskGroup(
            over: bannerTargets,
            limit: Self.portScanHostConcurrency,
            operation: { target in
                (target.0, target.1, await BannerProbe.fetch(target.1, openPorts: target.2))
            }
        ) { id, ip, title in
            guard self.portScanGeneration.isCurrent(generation) else { return false }
            guard let title else { failures += 1; return true }
            self.hostStore.update(id: id, ip: ip) { $0.serviceTitle = title }
            return true
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
                serviceTitle: h.serviceTitle,
                probeDescription: h.probeDescription
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
        elapsedWork?.cancel()
        elapsedWork = nil
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
                probeDescription: rec.probeDescription,
                status: .alive
            )
        }
        hostStore.replaceAll(with: restored)
        // Derived, not restored: a snapshot stores what was observed, so opening an old file
        // classifies it with today's rules rather than replaying the verdict it shipped with.
        reclassifyHosts()
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
        hostStore.remove(ids: ids)
        selection.subtract(ids)
    }

    /// Refreshes several hosts through a bounded window with one shared ARP table. An unbounded
    /// group spawned a `/sbin/ping` and a `/usr/sbin/arp` process per host, so "select all →
    /// refresh" on a /24 meant ~500 concurrent processes, each blocking a dispatch thread.
    func refreshHosts(_ ids: Set<Host.ID>) async {
        let targets = hosts.filter { ids.contains($0.id) }.map(\.id)
        guard !targets.isEmpty else { return }
        let arpTable = await ARPLookup.table()

        await withWindowedTaskGroup(
            over: targets,
            limit: Self.refreshConcurrency,
            operation: { id in await self.refreshHost(id, sharedARPTable: arpTable) }
        ) { _ in true }
    }

    func refreshHost(_ id: Host.ID, sharedARPTable: [String: String]? = nil) async {
        guard let target = hosts.first(where: { $0.id == id }) else { return }
        let ip = target.ip
        hostStore.update(id: id, ip: ip) { $0.status = .scanning }

        let result = await NetworkScanner.discover(ip)
        guard hostStore.index(of: id, ip: ip) != nil else { return }

        guard let result = result else {
            hostStore.update(id: id, ip: ip) {
                $0.status = .dead
                $0.rttMs = nil
                $0.ttl = nil
            }
            return
        }

        try? await Task.sleep(for: .milliseconds(HostEnricher.arpGraceMs))
        // Callers refreshing several hosts pass one shared table; each `table()` call is its own
        // `/usr/sbin/arp` process, so a bulk refresh would otherwise spawn one per host.
        let arpTable: [String: String]
        if let sharedARPTable {
            arpTable = sharedARPTable
        } else {
            arpTable = await ARPLookup.table()
        }
        let found = await HostEnricher.enrich(
            ip: ip,
            arpTable: arpTable,
            includeNetBIOS: profile.includeNetBIOS
        )

        hostStore.update(id: id, ip: ip) {
            $0.status = .alive
            $0.rttMs = result.rttMs
            $0.ttl = result.ttl
            if let h = found.hostname { $0.hostname = h }
            if let m = found.mac { $0.mac = m }
            if let v = found.vendor { $0.vendor = v }
            if let n = found.netbiosName { $0.netbiosName = n }
            if let w = found.workgroup { $0.workgroup = w }
        }
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
            hostStore.upsert(h)
            // Reclassify the row this event touched. Each phase adds evidence — discovery, then
            // enrichment's vendor, then the fingerprint's ports — so the verdict is re-derived as
            // the picture fills in rather than guessed once from the first thing seen.
            hostStore.reclassify(ip: h.ip) { classification(for: $0) }
        case .done:
            elapsedWork?.cancel()
            elapsedWork = nil
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
