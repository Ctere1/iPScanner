import Foundation

struct ScanRange: Hashable {
    let displayString: String
    let lowerBound: UInt32
    let upperBound: UInt32

    var addresses: [String] {
        guard upperBound >= lowerBound else { return [] }
        return (lowerBound...upperBound).map(IPv4.string(from:))
    }

    var hostCount: Int { Int(upperBound) - Int(lowerBound) + 1 }

    static func parse(_ input: String) -> ScanRange? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let r = ScanRange(cidr: trimmed) { return r }
        if let r = ScanRange(range: trimmed) { return r }
        if let r = ScanRange(singleIP: trimmed) { return r }
        return nil
    }

    init?(singleIP: String) {
        guard let value = IPv4.uint32(from: singleIP) else { return nil }
        self.lowerBound = value
        self.upperBound = value
        self.displayString = singleIP
    }

    /// Parses comma-separated input into multiple ranges.
    /// Returns the parsed list and the index (1-based) of the first invalid chunk, if any.
    static func parseAll(_ input: String) -> (ranges: [ScanRange], firstInvalidIndex: Int?) {
        let chunks = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var ranges: [ScanRange] = []
        for (idx, chunk) in chunks.enumerated() where !chunk.isEmpty {
            guard let r = parse(chunk) else {
                return (ranges, idx + 1)
            }
            ranges.append(r)
        }
        return (ranges, nil)
    }

    /// Upper limit on how many addresses a single scan may target.
    static let maxTargets = 65_536

    /// Total addresses spanned by `ranges`, counted without expanding them.
    /// Overlapping ranges are counted twice; this is an upper bound, not a deduplicated count.
    /// Saturates at `Int.max` rather than trapping.
    static func totalHostCount(_ ranges: [ScanRange]) -> Int {
        var total = 0
        for r in ranges where r.upperBound >= r.lowerBound {
            let (sum, overflow) = total.addingReportingOverflow(r.hostCount)
            if overflow { return .max }
            total = sum
        }
        return total
    }

    /// Combined unique addresses from multiple ranges, sorted numerically.
    /// Returns nil when the ranges span more than `limit` addresses. The count is checked
    /// before expansion, so an oversized range (`0.0.0.0/0` spans 4.3 billion) is rejected
    /// rather than allocated.
    static func uniqueAddresses(_ ranges: [ScanRange], limit: Int = maxTargets) -> [String]? {
        let bound = totalHostCount(ranges)
        guard bound <= limit else { return nil }
        var seen = Set<UInt32>()
        seen.reserveCapacity(bound)
        for r in ranges where r.upperBound >= r.lowerBound {
            for v in r.lowerBound...r.upperBound { seen.insert(v) }
        }
        return seen.sorted().map(IPv4.string(from:))
    }

    init?(cidr: String) {
        guard let slash = cidr.firstIndex(of: "/") else { return nil }
        let ipPart = String(cidr[..<slash])
        let prefixPart = String(cidr[cidr.index(after: slash)...])
        guard let prefix = Int(prefixPart), (0...32).contains(prefix) else { return nil }
        guard let ipInt = IPv4.uint32(from: ipPart) else { return nil }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let network = ipInt & mask
        let broadcast = network | ~mask

        if prefix < 31 {
            self.lowerBound = network &+ 1
            self.upperBound = broadcast == 0 ? 0 : broadcast &- 1
        } else {
            self.lowerBound = network
            self.upperBound = broadcast
        }
        self.displayString = cidr
    }

    init?(range: String) {
        let parts = range.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lo = IPv4.uint32(from: parts[0]),
              let hi = IPv4.uint32(from: parts[1]),
              lo <= hi else { return nil }
        self.lowerBound = lo
        self.upperBound = hi
        self.displayString = range
    }
}

enum IPv4 {
    static func uint32(from ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        return result
    }

    static func string(from value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
