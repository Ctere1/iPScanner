import XCTest
@testable import iPScanner

/// One merge rule, two callers. The GUI's copy and the CLI's copy had already drifted apart before
/// they were unified; these pin the behaviour so they cannot drift again.
final class HostMergeTests: XCTestCase {

    private func discovered(_ ip: String = "10.0.0.5") -> iPScanner.Host {
        iPScanner.Host(ip: ip, rttMs: 1.2, ttl: 64, status: .alive)
    }

    func testEnrichmentFillsInEmptyFields() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(
            ip: "10.0.0.5",
            hostname: "nas.local",
            mac: "aa:bb:cc:dd:ee:ff",
            vendor: "Synology",
            status: .alive
        ))
        XCTAssertEqual(host.hostname, "nas.local")
        XCTAssertEqual(host.mac, "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(host.vendor, "Synology")
    }

    /// The core rule: a nil field means "this phase did not look", not "this host has none".
    func testNilFieldsDoNotEraseWhatIsKnown() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(ip: "10.0.0.5", hostname: "nas.local", status: .alive))
        host.merge(iPScanner.Host(ip: "10.0.0.5", status: .alive))   // a phase that learned nothing
        XCTAssertEqual(host.hostname, "nas.local", "a later empty event must not wipe the hostname")
        XCTAssertEqual(host.rttMs, 1.2)
        XCTAssertEqual(host.ttl, 64)
    }

    /// The drift that made unifying this worth doing: the CLI's copy never merged these two, so
    /// `ipscanner` sent the UDP-137 query, parsed the reply, and threw the answer away.
    func testNetBIOSFieldsAreMerged() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(ip: "10.0.0.5", netbiosName: "OFFICE-PC", workgroup: "WORKGROUP", status: .alive))
        XCTAssertEqual(host.netbiosName, "OFFICE-PC")
        XCTAssertEqual(host.workgroup, "WORKGROUP")
    }

    func testServiceTitleIsMerged() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(ip: "10.0.0.5", serviceTitle: "DiskStation", status: .alive))
        XCTAssertEqual(host.serviceTitle, "DiskStation")
    }

    func testStatusAlwaysTakesTheUpdate() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(ip: "10.0.0.5", status: .dead))
        XCTAssertEqual(host.status, .dead, "status is not optional — the newest verdict wins")
    }

    func testLaterValuesOverwriteEarlierOnes() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(ip: "10.0.0.5", hostname: "old.local", status: .alive))
        host.merge(iPScanner.Host(ip: "10.0.0.5", hostname: "new.local", status: .alive))
        XCTAssertEqual(host.hostname, "new.local")
    }

    // MARK: - Ports

    func testPortsFromAProbedEventAreFolded() {
        var host: iPScanner.Host = discovered()
        host.merge(iPScanner.Host(ip: "10.0.0.5", openPorts: [80], scannedPorts: [80, 443], status: .alive))
        XCTAssertEqual(host.openPorts, [80])
        XCTAssertEqual(host.scannedPorts, [80, 443])
    }

    /// An event that probed nothing must leave the port verdicts alone — this is why the guard is
    /// on `scannedPorts` being empty rather than on `openPorts`.
    func testEventThatProbedNothingLeavesPortsAlone() {
        var host = iPScanner.Host(ip: "10.0.0.5", openPorts: [445], scannedPorts: [445, 22], status: .alive)
        host.merge(iPScanner.Host(ip: "10.0.0.5", hostname: "pc.local", status: .alive))
        XCTAssertEqual(host.openPorts, [445], "an enrichment event must not erase discovered ports")
        XCTAssertEqual(host.scannedPorts, [445, 22])
    }

    /// Distinct from the above: this event *did* look, and found nothing. That is a real finding.
    func testEventThatProbedAndFoundNothingClosesThePort() {
        var host = iPScanner.Host(ip: "10.0.0.5", openPorts: [8080], scannedPorts: [8080], status: .alive)
        host.merge(iPScanner.Host(ip: "10.0.0.5", openPorts: [], scannedPorts: [8080], status: .alive))
        XCTAssertEqual(host.openPorts, [], "a re-probe that found it closed must win")
        XCTAssertEqual(host.scannedPorts, [8080])
    }

    func testProbingANewPortKeepsPreviouslyFoundOnes() {
        var host = iPScanner.Host(ip: "10.0.0.5", openPorts: [445], scannedPorts: [445], status: .alive)
        host.merge(iPScanner.Host(ip: "10.0.0.5", openPorts: [22], scannedPorts: [22], status: .alive))
        XCTAssertEqual(host.openPorts, [22, 445], "scanning 22 must not erase the known 445")
        XCTAssertEqual(host.scannedPorts, [22, 445])
    }

    // MARK: - Identity

    func testMergePreservesIdentity() {
        var host: iPScanner.Host = discovered()
        let originalID = host.id
        host.merge(iPScanner.Host(ip: "10.0.0.5", hostname: "x.local", status: .alive))
        XCTAssertEqual(host.id, originalID, "merging must not re-identify the row")
        XCTAssertEqual(host.ip, "10.0.0.5")
        XCTAssertEqual(host.ipNumeric, IPv4.uint32(from: "10.0.0.5"))
    }
}
