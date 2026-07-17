import Foundation

/// The scanned hosts, plus the IP index used to find them.
///
/// A struct rather than an observable object on purpose: held as a stored property of the
/// `@Observable` controller, mutating it is a mutation of that property, so the UI still updates —
/// and the rules below stay testable without a UI, and usable from the CLI.
struct HostStore: Sendable {
    private(set) var hosts: [Host] = []

    /// IP → position in `hosts`. Enrichment merges one event per host per phase, so resolving the
    /// row by index keeps that path O(1); a `firstIndex(where:)` scan makes it O(n) per event.
    private var indexByIp: [String: Int] = [:]

    var isEmpty: Bool { hosts.isEmpty }
    var count: Int { hosts.count }
    var aliveCount: Int { hosts.filter { $0.status == .alive }.count }

    init(hosts: [Host] = []) {
        self.hosts = hosts
        rebuildIndex()
    }

    // MARK: - Index

    private mutating func rebuildIndex() {
        indexByIp = Dictionary(
            hosts.enumerated().map { ($0.element.ip, $0.offset) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Position of `id` in `hosts`, or nil if it is gone.
    ///
    /// The id check is the guard that matters: an IP can be reused by a different host across a
    /// restore, a delete, or a re-add, and an in-flight refresh holding a stale index would
    /// otherwise write one host's results onto another.
    func index(of id: Host.ID, ip: String) -> Int? {
        guard let idx = indexByIp[ip], hosts.indices.contains(idx), hosts[idx].id == id else {
            return nil
        }
        return idx
    }

    func host(id: Host.ID) -> Host? {
        hosts.first { $0.id == id }
    }

    // MARK: - Mutation

    /// Folds a scan event's host into the table, appending it if the IP is new.
    mutating func upsert(_ host: Host) {
        if let idx = indexByIp[host.ip], hosts.indices.contains(idx) {
            hosts[idx].merge(host)
        } else {
            indexByIp[host.ip] = hosts.count
            hosts.append(host)
        }
    }

    /// Applies `body` to the host identified by `id`, if it is still the host at `ip`.
    @discardableResult
    mutating func update(id: Host.ID, ip: String, _ body: (inout Host) -> Void) -> Bool {
        guard let idx = index(of: id, ip: ip) else { return false }
        body(&hosts[idx])
        return true
    }

    mutating func remove(ids: Set<Host.ID>) {
        guard !ids.isEmpty else { return }
        hosts.removeAll { ids.contains($0.id) }
        // Removal shifts every later element, so the whole index is rebuilt, not just the gaps.
        rebuildIndex()
    }

    mutating func replaceAll(with hosts: [Host]) {
        self.hosts = hosts
        // A snapshot file is user-supplied and may repeat an IP; last one wins rather than trapping.
        rebuildIndex()
    }

    mutating func removeAll() {
        hosts = []
        indexByIp = [:]
    }
}
