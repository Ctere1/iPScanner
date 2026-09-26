import XCTest
@testable import iPScanner

final class DeviceInformationTests: XCTestCase {
    func testMACFormatsAndInvalidInputs() {
        for value in ["28:6f:b9:00:00:01", "28-6F-B9-00-00-01", "286fb9000001", "286f.b900.0001", "28:6f:b9:0:0:1"] {
            XCTAssertEqual(MACAddress(value)?.canonical, "28:6f:b9:00:00:01")
        }
        for value in ["28:6f:b9:00:00", "28:6f:b9:00:00:ZZ", "000000000000", "28:6f:b9:00:00:001", "28-6f:b9:00:00:01"] { XCTAssertNil(MACAddress(value), value) }
    }
    func testAddressKindsAndVendorStatus() {
        let lookup = OUILookup(mas: [:], mam: [:], mal: ["286FB9": "Nokia", "2A6FB9": "Must not use"])
        XCTAssertEqual(lookup.resolve("28:6f:b9:00:00:01").vendor, "Nokia")
        XCTAssertEqual(lookup.resolve("2a:6f:b9:00:00:01").status, .localAddress)
        XCTAssertNil(lookup.resolve("2a:6f:b9:00:00:01").vendor)
        XCTAssertEqual(lookup.resolve("ff:ff:ff:ff:ff:ff").status, .nonUnicast)
        XCTAssertEqual(lookup.resolve("01:00:5e:00:00:01").status, .nonUnicast)
        XCTAssertEqual(lookup.resolve(nil).status, .macUnavailable)
        XCTAssertEqual(lookup.resolve("bad").status, .invalidAddress)
        XCTAssertEqual(lookup.resolve("30:00:00:00:00:01").status, .notFound)
    }
    func testPackagedRegistryContainsKnownAssignment() {
        XCTAssertEqual(OUILookup.shared.vendor(forMAC: "28:6f:b9:00:00:01"), "Nokia Shanghai Bell Co., Ltd.")
    }
    func testARPFixturesAndFailure() {
        let result = ARPLookup.parse("? (192.0.2.1) at 28:6f:b9:0:0:1 on en0 ifscope [ethernet]\n? (192.0.2.2) at (incomplete) on en0\n? (224.0.0.251) at 1:0:5e:0:0:fb on en0")
        XCTAssertEqual(result.entries, ["192.0.2.1": "28:6f:b9:00:00:01"])
        XCTAssertNil(result.error)
        XCTAssertNotNil(ARPLookup.parse("unexpected format").error)
        XCTAssertNil(ARPLookup.parse("").error)
    }
    func testConflictingInterfaceEntriesNeverReturnWrongMAC() {
        let first = "? (192.0.2.1) at 28:6f:b9:0:0:1 on en0"
        let second = "? (192.0.2.1) at 28:6f:b9:0:0:2 on en1"
        let result = ARPLookup.parse([first, second, first].joined(separator: "\n"))
        XCTAssertNil(result.entries["192.0.2.1"])
        XCTAssertNotNil(result.error)
    }
    func testARPRunnerReportsExitFailureAndTimeout() async {
        let failed = await ARPLookup.read(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        XCTAssertNotNil(failed.error)
        let start = Date()
        let timeout = await ARPLookup.read(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1)
        XCTAssertTrue(timeout.error?.contains("timed out") == true)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testARPRunnerCancellation() async {
        let task = Task { await ARPLookup.read(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"]) }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.error?.contains("cancelled") == true)
    }
    func testHostnameSuffixDoesNotIdentifyDevice() {
        XCTAssertEqual(DeviceClassifier.classify(Host(ip: "192.0.2.1", hostname: "iphone.hgw.local")), .phone)
        XCTAssertEqual(DeviceClassifier.classify(Host(ip: "192.0.2.1", hostname: "ck-mbp.hgw.local")), .mac)
        XCTAssertEqual(DeviceClassifier.classify(Host(ip: "192.0.2.1", hostname: "device.hgw.local", openPorts: [443])), .unknown)
        XCTAssertEqual(DeviceClassifier.classify(Host(ip: "192.0.2.1", hostname: "iphone.local", openPorts: [9100])), .unknown)
    }
    func testAuthoritativeMissingVendorClearsOldMerge() {
        let old = Host(ip: "192.0.2.1", mac: "28:6f:b9:00:00:01", vendor: "Nokia", vendorStatus: .matched)
        let update = Host(ip: "192.0.2.1", mac: "2a:6f:b9:00:00:01", vendorStatus: .localAddress)
        let result = old.merged(with: update)
        XCTAssertNil(result.vendor)
        XCTAssertEqual(result.vendorStatus, .localAddress)
        XCTAssertNil(old.merged(with: Host(ip: old.ip, vendorStatus: .queryFailed)).mac)
    }
    @MainActor func testBonjourRemovalRejectsLateResults() {
        var inventory = BonjourInventory()
        let id = "_http._tcp|local.|Printer|1"
        _ = inventory.reconcile(ids: [id], type: "_http._tcp")
        let token = inventory.tokens[id]!
        let record = MDNSDiscovery.ServiceRecord(displayType: "HTTP", serviceType: "_http._tcp", name: "Printer", ip: "192.0.2.1")
        inventory.accept(record, id: id, token: token)
        XCTAssertEqual(inventory.records.count, 1)
        _ = inventory.reconcile(ids: [], type: "_http._tcp")
        inventory.accept(record, id: id, token: token)
        XCTAssertTrue(inventory.records.isEmpty)
        _ = inventory.reconcile(ids: [id], type: "_http._tcp")
        inventory.accept(record, id: id, token: token)
        XCTAssertTrue(inventory.records.isEmpty)
    }
}
