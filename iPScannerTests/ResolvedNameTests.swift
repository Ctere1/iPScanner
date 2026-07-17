import XCTest
@testable import iPScanner

final class ResolvedNameTests: XCTestCase {

    func testPrefersDNSOverEverything() {
        let name = ResolvedName.best(dns: "router.lan", mdns: "Router", netbios: "ROUTER")
        XCTAssertEqual(name, ResolvedName(value: "router.lan", source: .dns))
    }

    /// The case that made the column useless: no PTR record, but the device announces itself.
    func testFallsBackToMDNSWhenNoPTR() {
        let name = ResolvedName.best(dns: nil, mdns: "Cemil MacBook Pro", netbios: nil)
        XCTAssertEqual(name, ResolvedName(value: "Cemil MacBook Pro", source: .mdns))
    }

    func testFallsBackToNetBIOSLast() {
        let name = ResolvedName.best(dns: nil, mdns: nil, netbios: "WORKSTATION")
        XCTAssertEqual(name, ResolvedName(value: "WORKSTATION", source: .netbios))
    }

    func testNilWhenNothingKnowsAName() {
        XCTAssertNil(ResolvedName.best(dns: nil, mdns: nil, netbios: nil))
    }

    /// An empty or blank string is not a name; it must not win over a real one further down.
    func testBlankSourcesAreSkipped() {
        XCTAssertEqual(
            ResolvedName.best(dns: "", mdns: "   ", netbios: "PC-01"),
            ResolvedName(value: "PC-01", source: .netbios)
        )
        XCTAssertNil(ResolvedName.best(dns: "", mdns: "", netbios: "  "))
    }

    func testNamesAreTrimmed() {
        XCTAssertEqual(ResolvedName.best(dns: "  host.lan\n", mdns: nil, netbios: nil)?.value, "host.lan")
    }

    /// Only non-DNS names are badged — a PTR name is what the column already claimed to show.
    func testOnlyNonDNSSourcesAreBadged() {
        XCTAssertNil(ResolvedName.Source.dns.badge)
        XCTAssertEqual(ResolvedName.Source.mdns.badge, "mDNS")
        XCTAssertEqual(ResolvedName.Source.netbios.badge, "NetBIOS")
    }
}
