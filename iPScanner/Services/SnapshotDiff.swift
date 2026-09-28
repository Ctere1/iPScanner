import Foundation

struct SnapshotDiff {
    /// Per-anchor change classification. Anchor = MAC if present, else IP.
    let changesByAnchor: [String: HostChange]
    let baselineCreatedAt: Date

    var newCount: Int {
        changesByAnchor.values.filter { if case .new = $0 { return true } else { return false } }.count
    }
    var modifiedCount: Int {
        changesByAnchor.values.filter { if case .modified = $0 { return true } else { return false } }.count
    }
    var missingCount: Int {
        changesByAnchor.values.filter { if case .missing = $0 { return true } else { return false } }.count
    }

    var missingRecords: [ScanSnapshot.HostRecord] {
        changesByAnchor.values.compactMap {
            if case .missing(let rec) = $0 { return rec } else { return nil }
        }
    }

    static func compute(current: [Host], baseline: ScanSnapshot) -> SnapshotDiff {
        // Two hosts can legitimately share a MAC-less anchor (both nil MAC, distinct
        // IPs would differ so this only collides on true duplicates); uniquing keeps
        // the diff from crashing on a malformed or hand-edited baseline/current set.
        let currentByAnchor: [String: Host] = Dictionary(
            current.compactMap { h -> (String, Host)? in
                guard h.status == .alive else { return nil }
                return (MACAddress.anchor(mac: h.mac, ip: h.ip), h)
            },
            uniquingKeysWith: { _, last in last }
        )

        let baselineByAnchor: [String: ScanSnapshot.HostRecord] = Dictionary(
            baseline.hosts.filter { $0.status == .alive }.map { (MACAddress.anchor(mac: $0.mac, ip: $0.ip), $0) },
            uniquingKeysWith: { _, last in last }
        )

        var changes: [String: HostChange] = [:]

        // Hosts present in current
        for (anchor, host) in currentByAnchor {
            if let baselineRec = baselineByAnchor[anchor] {
                let fields = changedFields(host: host, record: baselineRec)
                if !fields.isEmpty {
                    changes[anchor] = .modified(fields: fields)
                }
                // unchanged hosts intentionally omitted to keep the map sparse
            } else {
                changes[anchor] = .new
            }
        }

        // Hosts present only in baseline
        for (anchor, rec) in baselineByAnchor where currentByAnchor[anchor] == nil {
            changes[anchor] = .missing(record: rec)
        }

        return SnapshotDiff(changesByAnchor: changes, baselineCreatedAt: baseline.createdAt)
    }

    private static func changedFields(
        host: Host,
        record: ScanSnapshot.HostRecord
    ) -> [HostChange.ChangedField] {
        var diffs: [HostChange.ChangedField] = []
        if host.hostname != record.hostname { diffs.append(.hostname) }
        if host.mac.flatMap(MACAddress.init) != record.mac.flatMap(MACAddress.init) { diffs.append(.mac) }
        if host.vendor != record.vendor { diffs.append(.vendor) }
        if host.openPorts.sorted() != record.openPorts.sorted() { diffs.append(.openPorts) }
        if host.serviceTitle != record.serviceTitle { diffs.append(.serviceTitle) }
        return diffs
    }
}
