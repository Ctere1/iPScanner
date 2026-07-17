import Foundation

struct ScanSnapshot: Codable {
    /// Unchanged by the probeDescription field added below.
    ///
    /// Nothing reads this number — no code path rejects or migrates on it — and the format stays
    /// compatible in both directions regardless: the decoder takes every field as optional, and an
    /// older build ignores a key it does not know. Bumping it would imply a break that does not
    /// exist.
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let rangeInput: String
    let hosts: [HostRecord]
    let labels: [String: String]

    struct HostRecord: Codable, Equatable, Hashable, Sendable {
        let ip: String
        let hostname: String?
        let mac: String?
        let vendor: String?
        let rttMs: Double?
        let ttl: Int?
        let netbiosName: String?
        let workgroup: String?
        let openPorts: [Int]
        /// Ports actually probed; see `Host.scannedPorts`. Defaulted so existing call sites and
        /// tests keep compiling.
        let scannedPorts: [Int]
        let serviceTitle: String?
        /// What SSDP/UPnP and SNMP said.
        ///
        /// The device *type* is deliberately not stored alongside it. A snapshot records what was
        /// observed; the verdict is derived from that on load, so improving the rules improves old
        /// files too rather than freezing whatever the classifier believed on the day the file was
        /// written.
        let probeDescription: String?

        init(ip: String, hostname: String?, mac: String?, vendor: String?,
             rttMs: Double?, ttl: Int?, netbiosName: String? = nil,
             workgroup: String? = nil, openPorts: [Int], scannedPorts: [Int] = [],
             serviceTitle: String?, probeDescription: String? = nil) {
            self.ip = ip
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
        }

        // Custom decoder lets older `.ipscan.json` files (no `ttl` / `netbiosName`
        // / `workgroup`) still load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.ip = try c.decode(String.self, forKey: .ip)
            self.hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
            self.mac = try c.decodeIfPresent(String.self, forKey: .mac)
            self.vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
            self.rttMs = try c.decodeIfPresent(Double.self, forKey: .rttMs)
            self.ttl = try c.decodeIfPresent(Int.self, forKey: .ttl)
            self.netbiosName = try c.decodeIfPresent(String.self, forKey: .netbiosName)
            self.workgroup = try c.decodeIfPresent(String.self, forKey: .workgroup)
            self.openPorts = try c.decodeIfPresent([Int].self, forKey: .openPorts) ?? []
            // Files written before this key existed only ever recorded openPorts after a real port
            // scan, so a non-empty openPorts implies those ports were probed. Empty stays "never
            // probed", which is the honest reading of a file that never knew the difference.
            self.scannedPorts = try c.decodeIfPresent([Int].self, forKey: .scannedPorts) ?? self.openPorts
            self.serviceTitle = try c.decodeIfPresent(String.self, forKey: .serviceTitle)
            self.probeDescription = try c.decodeIfPresent(String.self, forKey: .probeDescription)
        }
    }
}

enum SnapshotIO {
    static func encode(_ snapshot: ScanSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> ScanSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanSnapshot.self, from: data)
    }

    static func defaultFileName() -> String {
        ExportNaming.fileName(ext: "ipscan.json")
    }
}
