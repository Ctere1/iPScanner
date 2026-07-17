import XCTest
@testable import iPScanner

final class HostPortMergeTests: XCTestCase {

    private func host(open: [Int] = [], scanned: [Int] = []) -> iPScanner.Host {
        iPScanner.Host(ip: "10.0.0.1", openPorts: open, scannedPorts: scanned, status: .alive)
    }

    // MARK: - The distinction the whole change exists for

    func testNeverScannedIsNotTheSameAsScannedAndClosed() {
        let untouched = host()
        let scannedNothingOpen = host(open: [], scanned: [445, 80])

        XCTAssertEqual(untouched.openPorts, scannedNothingOpen.openPorts, "both have no open ports…")
        XCTAssertNotEqual(untouched.scannedPorts, scannedNothingOpen.scannedPorts, "…but only one was looked at")

        XCTAssertEqual(PortScanner.displayList(open: untouched.openPorts, scanned: untouched.scannedPorts), "—")
        XCTAssertEqual(
            PortScanner.displayList(open: scannedNothingOpen.openPorts, scanned: scannedNothingOpen.scannedPorts),
            "none"
        )
    }

    func testDisplayListFormatsOpenPorts() {
        XCTAssertEqual(PortScanner.displayList(open: [22, 443], scanned: [22, 80, 443]), "22 (ssh), 443 (https)")
    }

    /// `formatList` stays a pure list formatter — the UI policy lives in `displayList`.
    func testFormatListStillReturnsEmptyStringForNoPorts() {
        XCTAssertEqual(PortScanner.formatList([]), "")
    }

    // MARK: - Merge rules

    func testProbingRecordsBothOpenAndScanned() {
        var h = host()
        h.mergePortResults(probed: [22, 80, 443], open: [22, 443])
        XCTAssertEqual(h.openPorts, [22, 443])
        XCTAssertEqual(h.scannedPorts, [22, 80, 443])
    }

    /// The regression the old `openPorts = new` assignment caused: a targeted scan of one port
    /// erased everything discovery had already found.
    func testUnprobedPortsKeepTheirVerdict() {
        var h = host(open: [445], scanned: [445, 80])
        h.mergePortResults(probed: [8080], open: [8080])
        XCTAssertEqual(h.openPorts, [445, 8080], "445 was not re-probed, so it must survive")
        XCTAssertEqual(h.scannedPorts, [80, 445, 8080])
    }

    func testReprobingAPortReplacesItsVerdict() {
        var h = host(open: [22, 445], scanned: [22, 445])
        h.mergePortResults(probed: [22], open: [])   // 22 has since closed
        XCTAssertEqual(h.openPorts, [445], "a re-probed port that no longer answers must drop out")
        XCTAssertEqual(h.scannedPorts, [22, 445])
    }

    func testScannedPortsAreUnionedNotReplaced() {
        var h = host(open: [], scanned: [22])
        h.mergePortResults(probed: [80, 443], open: [80])
        XCTAssertEqual(h.scannedPorts, [22, 80, 443])
    }

    func testResultsAreSorted() {
        var h = host()
        h.mergePortResults(probed: [443, 22, 80], open: [443, 22])
        XCTAssertEqual(h.openPorts, [22, 443])
        XCTAssertEqual(h.scannedPorts, [22, 80, 443])
    }

    func testMergingIsIdempotent() {
        var h = host()
        h.mergePortResults(probed: [22, 80], open: [22])
        let once = h
        h.mergePortResults(probed: [22, 80], open: [22])
        XCTAssertEqual(h.openPorts, once.openPorts)
        XCTAssertEqual(h.scannedPorts, once.scannedPorts)
    }

    // MARK: - Discovery carries its ports

    /// The ICMP path must not claim to have port-scanned anything.
    func testICMPDiscoverResultReportsNoPorts() {
        let result = DiscoverResult(rttMs: 1.2, ttl: 64)
        XCTAssertTrue(result.probedPorts.isEmpty)
        XCTAssertTrue(result.openPorts.isEmpty)
    }

    func testTCPFallbackDiscoverResultCarriesPorts() {
        let result = DiscoverResult(
            rttMs: 4.0, ttl: nil,
            probedPorts: NetworkScanner.tcpFallbackPorts,
            openPorts: [445]
        )
        XCTAssertEqual(result.openPorts, [445])
        XCTAssertEqual(Set(result.probedPorts), Set(NetworkScanner.tcpFallbackPorts))
    }
}
