import XCTest
@testable import iPScanner

/// First tests for the table's filtering — it was a computed property on an untested controller.
final class HostFilterTests: XCTestCase {

    private let byIP: [KeyPathComparator<iPScanner.Host>] = [
        KeyPathComparator(\iPScanner.Host.ipNumeric, order: .forward)
    ]

    private func apply(
        _ filter: HostFilter,
        to hosts: [iPScanner.Host],
        labels: [String: String] = [:]
    ) -> [iPScanner.Host] {
        filter.apply(
            to: hosts,
            label: { labels[$0.mac ?? $0.ip] },
            sortOrder: byIP
        )
    }

    private func host(
        _ ip: String,
        status: iPScanner.Host.Status = .alive,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        ports: [Int] = [],
        title: String? = nil
    ) -> iPScanner.Host {
        iPScanner.Host(
            ip: ip, hostname: hostname, mac: mac, vendor: vendor,
            openPorts: ports, scannedPorts: ports, serviceTitle: title, status: status
        )
    }

    // MARK: - Dead hosts

    func testDeadHostsAreHiddenByDefault() {
        let hosts = [host("10.0.0.1"), host("10.0.0.2", status: .dead)]
        XCTAssertEqual(apply(HostFilter(), to: hosts).map(\.ip), ["10.0.0.1"])
    }

    func testShowDeadIncludesThem() {
        let hosts = [host("10.0.0.1"), host("10.0.0.2", status: .dead)]
        var filter = HostFilter()
        filter.showDead = true
        XCTAssertEqual(apply(filter, to: hosts).count, 2)
    }

    /// A scanning host is neither alive nor dead yet, and must stay visible.
    func testScanningHostsStayVisible() {
        let hosts = [host("10.0.0.1", status: .scanning)]
        XCTAssertEqual(apply(HostFilter(), to: hosts).count, 1)
    }

    // MARK: - Scope filters

    func testOpenPortsFilter() {
        let hosts = [host("10.0.0.1", ports: [80]), host("10.0.0.2")]
        var filter = HostFilter()
        filter.hasOpenPorts = true
        XCTAssertEqual(apply(filter, to: hosts).map(\.ip), ["10.0.0.1"])
    }

    func testVendorFilterTreatsEmptyStringAsNoVendor() {
        let hosts = [host("10.0.0.1", vendor: "Apple"), host("10.0.0.2", vendor: ""), host("10.0.0.3")]
        var filter = HostFilter()
        filter.hasVendor = true
        XCTAssertEqual(apply(filter, to: hosts).map(\.ip), ["10.0.0.1"])
    }

    func testLabelFilter() {
        let hosts = [host("10.0.0.1"), host("10.0.0.2")]
        var filter = HostFilter()
        filter.hasLabel = true
        let result = apply(filter, to: hosts, labels: ["10.0.0.2": "Office NAS"])
        XCTAssertEqual(result.map(\.ip), ["10.0.0.2"])
    }

    func testFiltersCompose() {
        let hosts = [
            host("10.0.0.1", vendor: "Apple", ports: [80]),
            host("10.0.0.2", vendor: "Apple"),
            host("10.0.0.3", ports: [80])
        ]
        var filter = HostFilter()
        filter.hasVendor = true
        filter.hasOpenPorts = true
        XCTAssertEqual(apply(filter, to: hosts).map(\.ip), ["10.0.0.1"])
    }

    // MARK: - Search

    func testSearchMatchesEveryDisplayedField() {
        let hosts = [
            host("10.0.0.1", hostname: "printer.local"),
            host("10.0.0.2", mac: "aa:bb:cc:dd:ee:ff"),
            host("10.0.0.3", vendor: "Synology"),
            host("10.0.0.4", title: "DiskStation"),
            host("10.0.0.5")
        ]
        for (query, expected) in [
            ("printer", "10.0.0.1"),
            ("aa:bb", "10.0.0.2"),
            ("synology", "10.0.0.3"),
            ("diskstation", "10.0.0.4"),
            ("10.0.0.5", "10.0.0.5")
        ] {
            var filter = HostFilter()
            filter.query = query
            XCTAssertEqual(apply(filter, to: hosts).map(\.ip), [expected], "query: \(query)")
        }
    }

    func testSearchMatchesLabels() {
        let hosts = [host("10.0.0.1"), host("10.0.0.2")]
        var filter = HostFilter()
        filter.query = "office"
        let result = apply(filter, to: hosts, labels: ["10.0.0.2": "Office NAS"])
        XCTAssertEqual(result.map(\.ip), ["10.0.0.2"])
    }

    func testSearchIsCaseInsensitive() {
        let hosts = [host("10.0.0.1", hostname: "Printer.Local")]
        var filter = HostFilter()
        filter.query = "PRINTER"
        XCTAssertEqual(apply(filter, to: hosts).count, 1)
    }

    func testEmptyQueryFiltersNothing() {
        let hosts = [host("10.0.0.1"), host("10.0.0.2")]
        var filter = HostFilter()
        filter.query = ""
        XCTAssertEqual(apply(filter, to: hosts).count, 2)
    }

    // MARK: - Sorting

    func testSortsNumericallyNotLexically() {
        let hosts = [host("10.0.0.100"), host("10.0.0.9"), host("10.0.0.20")]
        XCTAssertEqual(apply(HostFilter(), to: hosts).map(\.ip), ["10.0.0.9", "10.0.0.20", "10.0.0.100"])
    }

    func testReverseSort() {
        let hosts = [host("10.0.0.1"), host("10.0.0.2")]
        let result = HostFilter().apply(
            to: hosts,
            label: { _ in nil },
            sortOrder: [KeyPathComparator(\iPScanner.Host.ipNumeric, order: .reverse)]
        )
        XCTAssertEqual(result.map(\.ip), ["10.0.0.2", "10.0.0.1"])
    }

    // MARK: - Scope flags

    /// `showDead` and `query` have their own controls, so "clear filters" must leave them alone.
    func testClearScopeFiltersLeavesShowDeadAndQueryAlone() {
        var filter = HostFilter()
        filter.showDead = true
        filter.query = "nas"
        filter.hasOpenPorts = true
        filter.identifiedDevice = true

        XCTAssertTrue(filter.hasActiveScopeFilters)
        filter.clearScopeFilters()

        XCTAssertFalse(filter.hasActiveScopeFilters)
        XCTAssertTrue(filter.showDead, "showDead is not a scope filter")
        XCTAssertEqual(filter.query, "nas", "the search query is not a scope filter")
    }

    func testNoScopeFiltersByDefault() {
        XCTAssertFalse(HostFilter().hasActiveScopeFilters)
    }
}
