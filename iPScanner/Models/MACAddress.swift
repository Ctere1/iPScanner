import Foundation

struct MACAddress: Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case universal, local, multicast, broadcast }
    let bytes: [UInt8]
    var hex: String { bytes.map { String(format: "%02X", $0) }.joined() }
    var canonical: String { bytes.map { String(format: "%02x", $0) }.joined(separator: ":") }
    var kind: Kind {
        if bytes.allSatisfy({ $0 == 255 }) { return .broadcast }
        if bytes[0] & 1 != 0 { return .multicast }
        return bytes[0] & 2 != 0 ? .local : .universal
    }
    static func anchor(mac: String?, ip: String) -> String {
        mac.flatMap { MACAddress($0)?.canonical } ?? ip
    }

    static func label(in labels: [String: String], mac: String?, ip: String) -> String? {
        let key = anchor(mac: mac, ip: ip)
        if let exact = labels[key] { return exact }
        guard let mac, let address = MACAddress(mac) else { return nil }
        // Keep labels saved under older unpadded ARP addresses.
        return labels.keys.sorted().first(where: { MACAddress($0) == address }).flatMap { labels[$0] }
    }

    init?(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [String]
        if value.contains(":") || value.contains("-") {
            let delimiter: Character = value.contains(":") ? ":" : "-"
            parts = value.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6, parts.allSatisfy({ (1...2).contains($0.count) }) else { return nil }
        } else {
            let flat: String
            if value.contains(".") {
                let groups = value.split(separator: ".", omittingEmptySubsequences: false)
                guard groups.count == 3, groups.allSatisfy({ $0.count == 4 }) else { return nil }
                flat = groups.joined()
            } else { flat = value }
            guard flat.utf8.count == 12 else { return nil }
            let chars = Array(flat)
            parts = stride(from: 0, to: 12, by: 2).map { String(chars[$0...($0 + 1)]) }
        }
        guard parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) } }) else { return nil }
        let parsed = parts.compactMap { UInt8($0, radix: 16) }
        guard parsed.count == 6, parsed.contains(where: { $0 != 0 }) else { return nil }
        bytes = parsed
    }
}

enum VendorStatus: String, Codable, Sendable {
    case matched, localAddress, nonUnicast, invalidAddress, notFound, macUnavailable, queryFailed, databaseUnavailable, historical
    var label: String {
        switch self {
        case .matched: "IEEE registry match"
        case .localAddress: "Locally administered MAC"
        case .nonUnicast: "Group / broadcast address"
        case .invalidAddress: "Invalid MAC address"
        case .notFound: "No registry match"
        case .macUnavailable: "MAC unavailable"
        case .queryFailed: "MAC query failed"
        case .databaseUnavailable: "Vendor database unavailable"
        case .historical: "Saved information — not refreshed"
        }
    }
}

struct VendorResolution: Sendable {
    let vendor: String?
    let status: VendorStatus
}
