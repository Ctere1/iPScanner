import XCTest
@testable import iPScanner

final class SnapshotDiffTests: XCTestCase {

    private func makeBaseline(records: [ScanSnapshot.HostRecord]) -> ScanSnapshot {
        ScanSnapshot(
            version: ScanSnapshot.currentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            rangeInput: "10.0.0.0/24",
            hosts: records,
            labels: [:]
        )
    }

    private func rec(_ ip: String, mac: String? = nil, hostname: String? = nil,
                     vendor: String? = nil, ports: [Int] = []) -> ScanSnapshot.HostRecord {
        .init(ip: ip, hostname: hostname, mac: mac, vendor: vendor, rttMs: nil,
              ttl: nil, openPorts: ports, serviceTitle: nil)
    }

    private func host(_ ip: String, mac: String? = nil, hostname: String? = nil,
                      vendor: String? = nil, ports: [Int] = []) -> iPScanner.Host {
        iPScanner.Host(ip: ip, hostname: hostname, mac: mac, vendor: vendor,
                       openPorts: ports, status: .alive)
    }

    func testNewHostAppearsAsNew() {
        let baseline = makeBaseline(records: [rec("10.0.0.1", mac: "AA:BB:CC:00:00:01")])
        let current = [
            host("10.0.0.1", mac: "AA:BB:CC:00:00:01"),
            host("10.0.0.50", mac: "AA:BB:CC:00:00:50")
        ]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        XCTAssertEqual(diff.newCount, 1)
        XCTAssertEqual(diff.modifiedCount, 0)
        XCTAssertEqual(diff.missingCount, 0)
        XCTAssertEqual(diff.changesByAnchor["aa:bb:cc:00:00:50"], .new)
    }

    func testRemovedHostAppearsAsMissing() {
        let baseline = makeBaseline(records: [
            rec("10.0.0.1", mac: "AA:BB:CC:00:00:01"),
            rec("10.0.0.99", mac: "AA:BB:CC:00:00:99", hostname: "old-printer")
        ])
        let current = [host("10.0.0.1", mac: "AA:BB:CC:00:00:01")]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        XCTAssertEqual(diff.missingCount, 1)
        XCTAssertEqual(diff.missingRecords.first?.hostname, "old-printer")
    }

    func testChangedPortsDetected() {
        let baseline = makeBaseline(records: [
            rec("10.0.0.1", mac: "AA:BB:CC:00:00:01", ports: [80])
        ])
        let current = [host("10.0.0.1", mac: "AA:BB:CC:00:00:01", ports: [80, 443])]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        XCTAssertEqual(diff.modifiedCount, 1)
        if case .modified(let fields) = diff.changesByAnchor["aa:bb:cc:00:00:01"] {
            XCTAssertTrue(fields.contains(.openPorts))
        } else {
            XCTFail("expected .modified change")
        }
    }

    func testIdenticalHostsProduceNoEntries() {
        let baseline = makeBaseline(records: [rec("10.0.0.1", mac: "AA:BB:CC:00:00:01", ports: [22])])
        let current = [host("10.0.0.1", mac: "AA:BB:CC:00:00:01", ports: [22])]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        XCTAssertEqual(diff.newCount, 0)
        XCTAssertEqual(diff.modifiedCount, 0)
        XCTAssertEqual(diff.missingCount, 0)
        XCTAssertTrue(diff.changesByAnchor.isEmpty)
    }

    func testIPAnchorFallbackWhenNoMAC() {
        let baseline = makeBaseline(records: [rec("10.0.0.1")])
        let current = [host("10.0.0.1", hostname: "router")]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        if case .modified(let fields) = diff.changesByAnchor["10.0.0.1"] {
            XCTAssertEqual(fields, [.hostname])
        } else {
            XCTFail("expected modified change keyed by IP")
        }
    }

    func testDeadHostsExcludedFromCurrent() {
        let baseline = makeBaseline(records: [rec("10.0.0.5", mac: "AA:BB:CC:00:00:05")])
        let dead = iPScanner.Host(ip: "10.0.0.5", mac: "AA:BB:CC:00:00:05", status: .dead)
        let diff = SnapshotDiff.compute(current: [dead], baseline: baseline)
        XCTAssertEqual(diff.missingCount, 1)
    }

    /// A hand-edited or externally produced baseline can repeat the same MAC (or,
    /// with no MAC, the same IP) across two records. compute() must not crash on
    /// the duplicate anchor key.
    func testDuplicateAnchorInBaselineDoesNotCrash() {
        let baseline = makeBaseline(records: [
            rec("10.0.0.1", mac: "AA:BB:CC:00:00:01", hostname: "first"),
            rec("10.0.0.2", mac: "AA:BB:CC:00:00:01", hostname: "second")
        ])
        let current = [host("10.0.0.1", mac: "AA:BB:CC:00:00:01")]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        XCTAssertNotNil(diff)
    }

    /// Two alive current hosts sharing the same anchor (both with a nil MAC and,
    /// pathologically, the same IP) must not crash compute() either.
    func testDuplicateAnchorInCurrentDoesNotCrash() {
        let baseline = makeBaseline(records: [rec("10.0.0.1")])
        let current = [host("10.0.0.1", hostname: "a"), host("10.0.0.1", hostname: "b")]
        let diff = SnapshotDiff.compute(current: current, baseline: baseline)
        XCTAssertNotNil(diff)
    }
    func testLegacyShortMACDoesNotCreateFalseDiff() {
        let baseline = makeBaseline(records: [rec("10.0.0.1", mac: "a8:bb:cc:0:0:1")])
        let current = [host("10.0.0.1", mac: "A8-BB-CC-00-00-01")]
        XCTAssertTrue(SnapshotDiff.compute(current: current, baseline: baseline).changesByAnchor.isEmpty)
    }
    func testLegacyLabelSurvivesCanonicalMACFormatting() {
        let labels = ["a8:bb:cc:0:0:1": "Office", "10.0.0.2": "IP label"]
        XCTAssertEqual(MACAddress.label(in: labels, mac: "A8BB.CC00.0001", ip: "10.0.0.1"), "Office")
        XCTAssertEqual(MACAddress.label(in: labels, mac: nil, ip: "10.0.0.2"), "IP label")
    }

}
