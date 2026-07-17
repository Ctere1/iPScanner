import XCTest
@testable import iPScanner

final class ICMPPingTests: XCTestCase {

    // MARK: - Packet construction

    func testEchoRequestHeader() {
        let packet = ICMPPing.echoRequest(token: 0)
        XCTAssertEqual(packet[0], 8, "type must be echo request")
        XCTAssertEqual(packet[1], 0, "code must be 0")
        XCTAssertEqual(packet[6], 0)
        XCTAssertEqual(packet[7], 1, "sequence")
    }

    func testEchoRequestCarriesTokenBigEndian() {
        let packet = ICMPPing.echoRequest(token: 0xDEADBEEF)
        XCTAssertEqual(Array(packet.suffix(4)), [0xDE, 0xAD, 0xBE, 0xEF])
    }

    /// The checksum of a packet that already contains its own checksum is zero — the standard
    /// self-check, and the property a receiver relies on.
    func testChecksumOfCompletePacketIsZero() {
        let packet = ICMPPing.echoRequest(token: 0x12345678)
        XCTAssertEqual(ICMPPing.checksum(packet), 0)
    }

    func testChecksumHandlesOddLength() {
        // Must not trap on a trailing odd byte.
        XCTAssertNotNil(ICMPPing.checksum([0x01, 0x02, 0x03]))
    }

    // MARK: - Reply parsing

    /// Builds a reply as the kernel delivers it: IPv4 header, then the ICMP message.
    private func reply(
        type: UInt8 = 0,
        ttl: UInt8 = 64,
        token: UInt32,
        payloadPrefix: String = "iPScan",
        headerWords: UInt8 = 5,
        version: UInt8 = 4
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(headerWords) * 4)
        bytes[0] = (version << 4) | headerWords
        bytes[8] = ttl
        bytes += [type, 0, 0, 0, 0, 0, 0, 1]
        bytes += Array(payloadPrefix.utf8)
        bytes += [
            UInt8(truncatingIfNeeded: token >> 24),
            UInt8(truncatingIfNeeded: token >> 16),
            UInt8(truncatingIfNeeded: token >> 8),
            UInt8(truncatingIfNeeded: token)
        ]
        return bytes
    }

    func testParsesEchoReplyAndReadsTTL() {
        let parsed = ICMPPing.parseEchoReply(reply(ttl: 128, token: 0xAABBCCDD), expecting: 0xAABBCCDD)
        XCTAssertEqual(parsed, ICMPPing.EchoReply(ttl: 128))
    }

    /// Options make the header longer than 20 bytes; TTL and the ICMP offset must still be right.
    func testParsesReplyWithIPOptions() {
        let parsed = ICMPPing.parseEchoReply(
            reply(ttl: 255, token: 1, headerWords: 6),
            expecting: 1
        )
        XCTAssertEqual(parsed, ICMPPing.EchoReply(ttl: 255))
    }

    /// Another probe's reply must not be counted as ours.
    func testRejectsForeignToken() {
        XCTAssertNil(ICMPPing.parseEchoReply(reply(token: 0x11111111), expecting: 0x22222222))
    }

    /// Type 3 (destination unreachable) and 11 (TTL exceeded) mean the host is not alive.
    func testRejectsNonEchoReplyTypes() {
        for type: UInt8 in [3, 8, 11] {
            XCTAssertNil(
                ICMPPing.parseEchoReply(reply(type: type, token: 7), expecting: 7),
                "type \(type) must not count as a reply"
            )
        }
    }

    func testRejectsWrongPayloadPrefix() {
        XCTAssertNil(
            ICMPPing.parseEchoReply(reply(token: 7, payloadPrefix: "XXXXXX"), expecting: 7)
        )
    }

    func testRejectsNonIPv4() {
        XCTAssertNil(ICMPPing.parseEchoReply(reply(token: 7, version: 6), expecting: 7))
    }

    // MARK: - Malformed input must not trap

    /// These bytes come off the network, so every truncation must return nil rather than crash.
    func testTruncatedPacketsAreRejectedNotTrapped() {
        let full = reply(token: 0x99)
        for length in 0..<full.count {
            XCTAssertNil(
                ICMPPing.parseEchoReply(Array(full.prefix(length)), expecting: 0x99),
                "prefix of length \(length) should be rejected"
            )
        }
    }

    func testRejectsImpossibleHeaderLength() {
        // headerWords < 5 is invalid; the offset arithmetic must not run off the array.
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes[0] = (4 << 4) | 2
        XCTAssertNil(ICMPPing.parseEchoReply(bytes, expecting: 0))
    }

    func testEmptyInput() {
        XCTAssertNil(ICMPPing.parseEchoReply([], expecting: 0))
    }
}
