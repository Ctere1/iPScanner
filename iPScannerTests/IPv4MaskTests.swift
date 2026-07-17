import XCTest
@testable import iPScanner

/// ScanRange, SubnetCalculator and NetworkInterface each carried their own copy of this arithmetic.
/// These tests pin the shared one, and the last case is why sharing it mattered.
final class IPv4MaskTests: XCTestCase {

    private func ip(_ s: String) -> UInt32 { IPv4.uint32(from: s)! }

    func testMaskForCommonPrefixes() {
        XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: 24)), "255.255.255.0")
        XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: 16)), "255.255.0.0")
        XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: 8)), "255.0.0.0")
        XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: 30)), "255.255.255.252")
        XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: 32)), "255.255.255.255")
    }

    /// `UInt32.max << 32` is an undefined shift, and only a /0 reaches it — a copy that forgot the
    /// guard looked correct on every prefix anyone would normally type.
    func testSlashZeroDoesNotShiftOffTheEnd() {
        XCTAssertEqual(IPv4.mask(bits: 0), 0)
        XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: 0)), "0.0.0.0")
        XCTAssertEqual(IPv4.network(ip("192.168.1.55"), bits: 0), 0)
        XCTAssertEqual(IPv4.string(from: IPv4.broadcast(ip("192.168.1.55"), bits: 0)), "255.255.255.255")
    }

    func testOutOfRangePrefixIsNotAShift() {
        XCTAssertEqual(IPv4.mask(bits: 33), 0)
        XCTAssertEqual(IPv4.mask(bits: -1), 0)
    }

    func testNetworkMasksHostBits() {
        XCTAssertEqual(IPv4.string(from: IPv4.network(ip("10.0.0.42"), bits: 24)), "10.0.0.0")
        XCTAssertEqual(IPv4.string(from: IPv4.network(ip("192.168.1.200"), bits: 16)), "192.168.0.0")
    }

    func testBroadcastFillsHostBits() {
        XCTAssertEqual(IPv4.string(from: IPv4.broadcast(ip("10.0.0.42"), bits: 24)), "10.0.0.255")
        XCTAssertEqual(IPv4.string(from: IPv4.broadcast(ip("192.168.1.0"), bits: 30)), "192.168.1.3")
    }

    func testSlash32IsItsOwnNetworkAndBroadcast() {
        let single = ip("8.8.8.8")
        XCTAssertEqual(IPv4.network(single, bits: 32), single)
        XCTAssertEqual(IPv4.broadcast(single, bits: 32), single)
    }

    /// The three former implementations must not have disagreed — this is the assertion that the
    /// consolidation preserved behaviour rather than picking a winner.
    func testAgreesWithSubnetCalculator() {
        for cidr in ["10.0.0.42/24", "192.168.1.0/30", "172.16.5.7/16", "8.8.8.8/32"] {
            let parts = cidr.split(separator: "/")
            let addr = ip(String(parts[0]))
            let bits = Int(parts[1])!
            let summary = SubnetCalculator.summarize(cidr)
            XCTAssertEqual(IPv4.string(from: IPv4.network(addr, bits: bits)), summary?.network, cidr)
            XCTAssertEqual(IPv4.string(from: IPv4.broadcast(addr, bits: bits)), summary?.broadcast, cidr)
            XCTAssertEqual(IPv4.string(from: IPv4.mask(bits: bits)), summary?.netmask, cidr)
        }
    }
}
