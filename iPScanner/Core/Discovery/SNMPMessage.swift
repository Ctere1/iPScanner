import Foundation

enum SNMPValue: Hashable, Sendable {
    case octetString(String)
    case oid(String)
    case integer(Int)
    /// A type we can decode the length of but do not interpret.
    case other
}

struct SNMPResult: Hashable, Sendable {
    /// sysDescr — a free-text description. "HP ETHERNET MULTI-ENVIRONMENT", "RouterOS RB750",
    /// "Linux nas 5.10". The most useful single string a network device will volunteer.
    var sysDescr: String?
    /// sysObjectID — the vendor's enterprise OID. Unambiguous where sysDescr is prose.
    var sysObjectID: String?
    var sysName: String?

    var isEmpty: Bool { sysDescr == nil && sysObjectID == nil && sysName == nil }
}

/// SNMPv2c GET, encoded by hand.
///
/// ~150 lines of BER rather than a dependency, in a project that advertises no third-party code.
/// It is also the most testable thing here: the encoding is deterministic, so a request is a golden
/// byte array and a response is a captured packet — no device and no network required.
enum SNMPMessage {
    static let port: UInt16 = 161

    static let sysDescr = "1.3.6.1.2.1.1.1.0"
    static let sysObjectID = "1.3.6.1.2.1.1.2.0"
    static let sysName = "1.3.6.1.2.1.1.5.0"

    static let defaultOIDs = [sysDescr, sysObjectID, sysName]

    // BER tags.
    private enum Tag {
        static let integer: UInt8 = 0x02
        static let octetString: UInt8 = 0x04
        static let null: UInt8 = 0x05
        static let objectID: UInt8 = 0x06
        static let sequence: UInt8 = 0x30
        static let getRequest: UInt8 = 0xA0
        static let getResponse: UInt8 = 0xA2
    }

    // MARK: - Encoding

    /// A v2c GET for `oids`.
    ///
    /// - Parameter requestID: echoed back in the reply. Passed in rather than randomised inside so
    ///   the encoding stays deterministic and therefore testable.
    static func get(oids: [String], community: String = "public", requestID: Int32) -> Data {
        // Each variable binding is (oid, NULL) — NULL being "this is what I am asking for".
        let bindings = oids.map { oid in
            encode(tag: Tag.sequence, encodeOID(oid) + [Tag.null, 0x00])
        }.flatMap { $0 }

        let pdu = encode(tag: Tag.getRequest,
                         encodeInteger(Int(requestID))
                         + encodeInteger(0)              // error-status
                         + encodeInteger(0)              // error-index
                         + encode(tag: Tag.sequence, bindings))

        let message = encodeInteger(1)                   // version: 1 == SNMPv2c
            + encode(tag: Tag.octetString, Array(community.utf8))
            + pdu

        return Data(encode(tag: Tag.sequence, message))
    }

    private static func encode(tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + encodeLength(content.count) + content
    }

    /// Short form below 128, long form above — the length of the length comes first.
    private static func encodeLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    private static func encodeInteger(_ value: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var remaining = value
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining != 0 && remaining != -1
        // A leading bit of 1 would read as negative, so pad.
        if let first = bytes.first, first & 0x80 != 0, value >= 0 {
            bytes.insert(0x00, at: 0)
        }
        return encode(tag: Tag.integer, bytes)
    }

    private static func encodeOID(_ oid: String) -> [UInt8] {
        let parts = oid.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return encode(tag: Tag.objectID, []) }
        // The first two arcs share one byte: 40*x + y. A quirk of BER, not of SNMP.
        var bytes: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for part in parts.dropFirst(2) {
            bytes += encodeBase128(part)
        }
        return encode(tag: Tag.objectID, bytes)
    }

    /// Seven bits per byte, high bit set on every byte but the last.
    private static func encodeBase128(_ value: Int) -> [UInt8] {
        guard value > 0 else { return [0x00] }
        var bytes: [UInt8] = []
        var remaining = value
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F), at: 0)
            remaining >>= 7
        }
        for index in 0..<(bytes.count - 1) {
            bytes[index] |= 0x80
        }
        return bytes
    }

    // MARK: - Decoding

    /// oid → value, from a GetResponse. nil for anything that is not one.
    static func parseResponse(_ data: Data) -> [String: SNMPValue]? {
        var cursor = Cursor(Array(data))
        guard let message = cursor.readTLV(), message.tag == Tag.sequence else { return nil }

        var body = Cursor(message.value)
        guard body.readTLV()?.tag == Tag.integer else { return nil }        // version
        guard body.readTLV()?.tag == Tag.octetString else { return nil }    // community
        guard let pdu = body.readTLV(), pdu.tag == Tag.getResponse else { return nil }

        var pduBody = Cursor(pdu.value)
        guard pduBody.readTLV() != nil,                                     // request-id
              let errorStatus = pduBody.readTLV(),
              pduBody.readTLV() != nil,                                     // error-index
              let bindings = pduBody.readTLV(), bindings.tag == Tag.sequence
        else { return nil }

        // A non-zero error-status means the agent refused; treat it as no answer rather than
        // reporting whatever half-filled bindings came back with it.
        if let status = decodeInteger(errorStatus.value), status != 0 { return nil }

        var result: [String: SNMPValue] = [:]
        var list = Cursor(bindings.value)
        while let binding = list.readTLV(), binding.tag == Tag.sequence {
            var pair = Cursor(binding.value)
            guard let oidTLV = pair.readTLV(), oidTLV.tag == Tag.objectID,
                  let valueTLV = pair.readTLV(),
                  let oid = decodeOID(oidTLV.value) else { continue }
            result[oid] = decodeValue(valueTLV)
        }
        return result.isEmpty ? nil : result
    }

    /// The three fields the classifier cares about, named.
    static func result(from data: Data) -> SNMPResult? {
        guard let values = parseResponse(data) else { return nil }
        var result = SNMPResult()
        if case .octetString(let s)? = values[sysDescr] { result.sysDescr = s }
        if case .oid(let s)? = values[sysObjectID] { result.sysObjectID = s }
        if case .octetString(let s)? = values[sysName] { result.sysName = s }
        return result.isEmpty ? nil : result
    }

    private static func decodeValue(_ tlv: TLV) -> SNMPValue {
        switch tlv.tag {
        case Tag.octetString:
            return .octetString(String(decoding: tlv.value, as: UTF8.self))
        case Tag.objectID:
            return decodeOID(tlv.value).map { .oid($0) } ?? .other
        case Tag.integer:
            return decodeInteger(tlv.value).map { .integer($0) } ?? .other
        default:
            return .other
        }
    }

    private static func decodeInteger(_ bytes: [UInt8]) -> Int? {
        guard !bytes.isEmpty else { return nil }
        var value = 0
        for byte in bytes { value = (value << 8) | Int(byte) }
        return value
    }

    private static func decodeOID(_ bytes: [UInt8]) -> String? {
        guard let first = bytes.first else { return nil }
        var arcs = [Int(first) / 40, Int(first) % 40]
        var current = 0
        for byte in bytes.dropFirst() {
            current = (current << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                arcs.append(current)
                current = 0
            }
        }
        return arcs.map(String.init).joined(separator: ".")
    }

    private struct TLV {
        let tag: UInt8
        let value: [UInt8]
    }

    /// Walks a byte array, handing back one tag-length-value at a time. Refuses to read past the
    /// end, so a truncated packet yields nil rather than trapping.
    private struct Cursor {
        private let bytes: [UInt8]
        private var offset = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func readTLV() -> TLV? {
            guard offset + 2 <= bytes.count else { return nil }
            let tag = bytes[offset]
            offset += 1

            var length = Int(bytes[offset])
            offset += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count > 0, offset + count <= bytes.count else { return nil }
                length = 0
                for _ in 0..<count {
                    length = (length << 8) | Int(bytes[offset])
                    offset += 1
                }
            }

            guard offset + length <= bytes.count else { return nil }
            let value = Array(bytes[offset..<(offset + length)])
            offset += length
            return TLV(tag: tag, value: value)
        }
    }
}
