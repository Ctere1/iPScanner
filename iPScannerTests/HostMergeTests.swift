import XCTest
@testable import iPScanner

/// `Host.merged(with:)` is the single merge implementation shared by the GUI
/// scan loop (`ScanController.handle(event:)`) and the CLI (`EntryPoint`).
/// Before this, the CLI had its own copy that dropped `netbiosName`/`workgroup`
/// — these tests pin down the fields a merge must preserve so the two surfaces
/// can't silently diverge again.
final class HostMergeTests: XCTestCase {

    func testMergePreservesNetBIOSFields() {
        let existing = iPScanner.Host(ip: "10.0.0.1", hostname: "old", status: .alive)
        let update = iPScanner.Host(
            ip: "10.0.0.1", netbiosName: "SRV01", workgroup: "CORP", status: .alive
        )
        let merged = existing.merged(with: update)
        XCTAssertEqual(merged.netbiosName, "SRV01")
        XCTAssertEqual(merged.workgroup, "CORP")
        // Fields the update left nil are kept from the existing record.
        XCTAssertEqual(merged.hostname, "old")
    }

    func testMergeKeepsExistingOpenPortsWhenUpdateHasNone() {
        let existing = iPScanner.Host(ip: "10.0.0.1", openPorts: [22, 80], status: .alive)
        let update = iPScanner.Host(ip: "10.0.0.1", openPorts: [], status: .alive)
        let merged = existing.merged(with: update)
        XCTAssertEqual(merged.openPorts, [22, 80])
    }

    func testMergeReplacesOpenPortsWhenUpdateHasSome() {
        let existing = iPScanner.Host(ip: "10.0.0.1", openPorts: [22], status: .alive)
        let update = iPScanner.Host(ip: "10.0.0.1", openPorts: [22, 443], status: .alive)
        let merged = existing.merged(with: update)
        XCTAssertEqual(merged.openPorts, [22, 443])
    }

    func testMergeAlwaysAdoptsUpdateStatus() {
        let existing = iPScanner.Host(ip: "10.0.0.1", status: .alive)
        let update = iPScanner.Host(ip: "10.0.0.1", status: .dead)
        XCTAssertEqual(existing.merged(with: update).status, .dead)
    }
}
