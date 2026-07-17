import XCTest
@testable import iPScanner

/// `arp -an` and `ping -c 1` output parsing. Both used to live inside the Process block that ran
/// the command, so neither could be tested without spawning a real subprocess against a real
/// network — which is why neither ever was.
final class OutputParsingTests: XCTestCase {

    // MARK: - ARPLookup.parse

    func testParsesArpTable() {
        let output = """
        ? (192.168.1.1) at 3c:37:86:1a:2b:3c on en0 ifscope [ethernet]
        ? (192.168.1.42) at a4:83:e7:1f:2e:3d on en0 ifscope [ethernet]
        """
        let table = ARPLookup.parse(output)
        XCTAssertEqual(table["192.168.1.1"], "3c:37:86:1a:2b:3c")
        XCTAssertEqual(table["192.168.1.42"], "a4:83:e7:1f:2e:3d")
        XCTAssertEqual(table.count, 2)
    }

    func testArpMacIsLowercased() {
        let table = ARPLookup.parse("? (10.0.0.5) at AA:BB:CC:DD:EE:FF on en0 ifscope [ethernet]")
        XCTAssertEqual(table["10.0.0.5"], "aa:bb:cc:dd:ee:ff")
    }

    /// An incomplete entry means the ARP request went unanswered — there is no MAC to record, and
    /// treating the literal string "(incomplete)" as one would be worse than knowing nothing.
    func testArpSkipsIncompleteEntries() {
        let output = """
        ? (192.168.1.1) at 3c:37:86:1a:2b:3c on en0 ifscope [ethernet]
        ? (192.168.1.99) at (incomplete) on en0 ifscope [ethernet]
        """
        let table = ARPLookup.parse(output)
        XCTAssertEqual(table.count, 1)
        XCTAssertNil(table["192.168.1.99"])
    }

    func testArpHandlesNamedHostsAndShortMACs() {
        // macOS prints octets without a leading zero: 3c:7:86 rather than 3c:07:86.
        let output = "router.local (192.168.1.1) at 3c:7:86:1a:2b:3c on en0 ifscope [ethernet]"
        let table = ARPLookup.parse(output)
        XCTAssertEqual(table["192.168.1.1"], "3c:7:86:1a:2b:3c")
    }

    func testArpEmptyOutput() {
        XCTAssertTrue(ARPLookup.parse("").isEmpty)
        XCTAssertTrue(ARPLookup.parse("arp: no entries\n").isEmpty)
    }

    // MARK: - NetworkScanner.parsePingOutput

    func testParsesPingRttAndTTL() {
        let output = """
        PING 192.168.1.1 (192.168.1.1): 56 data bytes
        64 bytes from 192.168.1.1: icmp_seq=0 ttl=64 time=1.234 ms
        """
        let result = NetworkScanner.parsePingOutput(output)
        XCTAssertEqual(result?.rttMs, 1.234)
        XCTAssertEqual(result?.ttl, 64)
    }

    /// TTL is the OS fingerprint the classifier leans on: 64 Linux/Apple, 128 Windows, 255 gear.
    func testParsesWindowsStyleTTL() {
        let output = "64 bytes from 10.0.0.7: icmp_seq=0 ttl=128 time=0.5 ms"
        XCTAssertEqual(NetworkScanner.parsePingOutput(output)?.ttl, 128)
    }

    func testPingWithoutTTLStillYieldsRtt() {
        let output = "64 bytes from 10.0.0.7: icmp_seq=0 time=2.5 ms"
        let result = NetworkScanner.parsePingOutput(output)
        XCTAssertEqual(result?.rttMs, 2.5)
        XCTAssertNil(result?.ttl, "absent TTL must stay absent rather than defaulting")
    }

    func testPingTimeoutOutputYieldsNil() {
        let output = """
        PING 192.168.1.99 (192.168.1.99): 56 data bytes
        Request timeout for icmp_seq 0
        """
        XCTAssertNil(NetworkScanner.parsePingOutput(output))
    }

    func testPingHandlesSpaceBeforeUnit() {
        XCTAssertEqual(NetworkScanner.parsePingOutput("ttl=64 time=0.087 ms")?.rttMs, 0.087)
    }

    func testPingGarbageYieldsNil() {
        XCTAssertNil(NetworkScanner.parsePingOutput(""))
        XCTAssertNil(NetworkScanner.parsePingOutput("ping: cannot resolve host: Unknown host"))
    }
}
