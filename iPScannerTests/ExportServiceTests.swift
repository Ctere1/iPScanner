import XCTest
@testable import iPScanner

final class ExportServiceTests: XCTestCase {

    private func makeRow(
        ip: String = "10.0.0.1",
        label: String? = nil,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        rttMs: Double? = nil,
        ttl: Int? = nil,
        openPorts: [Int] = []
    ) -> ExportService.Row {
        ExportService.Row(
            ip: ip, label: label, hostname: hostname, mac: mac,
            vendor: vendor, rttMs: rttMs, ttl: ttl, openPorts: openPorts
        )
    }

    func testCSVHeader() {
        let csv = ExportService.csv(rows: [])
        XCTAssertTrue(csv.hasPrefix("IP,Label,Hostname,MAC,Vendor,RTT (ms),TTL,Open Ports"))
    }

    func testCSVBasic() {
        let csv = ExportService.csv(rows: [
            makeRow(
                label: "Router",
                hostname: "hgw.local",
                mac: "AA:BB:CC:DD:EE:FF",
                vendor: "Vendor Inc",
                rttMs: 1.5,
                ttl: 64,
                openPorts: [80, 443]
            )
        ])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "10.0.0.1,Router,hgw.local,AA:BB:CC:DD:EE:FF,Vendor Inc,1.5,64,80;443")
    }

    func testCSVEscapesComma() {
        let csv = ExportService.csv(rows: [
            makeRow(label: "Vendor Inc, Co.")
        ])
        XCTAssertTrue(csv.contains("\"Vendor Inc, Co.\""))
    }

    func testCSVEscapesQuotes() {
        let csv = ExportService.csv(rows: [
            makeRow(label: "Has \"quotes\"")
        ])
        // RFC 4180: " becomes "" and the field is wrapped in quotes
        XCTAssertTrue(csv.contains("\"Has \"\"quotes\"\"\""))
    }

    func testCSVEscapesNewline() {
        let csv = ExportService.csv(rows: [
            makeRow(label: "Line one\nLine two")
        ])
        XCTAssertTrue(csv.contains("\"Line one\nLine two\""))
    }

    func testCSVNilFields() {
        let csv = ExportService.csv(rows: [makeRow()])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        // ip + 7 empty cells (label, hostname, mac, vendor, rtt, ttl, ports)
        XCTAssertTrue(lines[1].hasPrefix("10.0.0.1,,,,,,,"))
    }

    func testCSVMultipleRows() {
        let csv = ExportService.csv(rows: [
            makeRow(ip: "10.0.0.1", openPorts: [80]),
            makeRow(ip: "10.0.0.2", openPorts: [22, 443])
        ])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)  // header + 2 rows
        XCTAssertTrue(lines[1].contains("10.0.0.1"))
        XCTAssertTrue(lines[1].contains(",80"))
        XCTAssertTrue(lines[2].contains("10.0.0.2"))
        XCTAssertTrue(lines[2].contains("22;443"))
    }

    // MARK: - IP:Port export

    func testIPPortListBasic() {
        let out = ExportService.ipPortList(rows: [
            makeRow(ip: "10.0.0.1", openPorts: [22, 80]),
            makeRow(ip: "10.0.0.2", openPorts: [443])
        ])
        XCTAssertEqual(out, "10.0.0.1:22\n10.0.0.1:80\n10.0.0.2:443\n")
    }

    func testIPPortListSkipsHostsWithNoPorts() {
        let out = ExportService.ipPortList(rows: [
            makeRow(ip: "10.0.0.1", openPorts: []),
            makeRow(ip: "10.0.0.2", openPorts: [22])
        ])
        XCTAssertEqual(out, "10.0.0.2:22\n")
    }

    func testIPPortListEmpty() {
        let out = ExportService.ipPortList(rows: [])
        XCTAssertEqual(out, "")
    }

    // MARK: - TXT report

    func testTextReportContainsHeader() {
        let out = ExportService.textReport(
            rows: [],
            rangeInput: "10.0.0.0/24",
            scannedTotal: 254,
            aliveCount: 5
        )
        XCTAssertTrue(out.contains("iPScanner Report"))
        XCTAssertTrue(out.contains("Range: 10.0.0.0/24"))
        XCTAssertTrue(out.contains("Scanned: 254"))
        XCTAssertTrue(out.contains("Alive: 5"))
    }

    func testTextReportRendersRows() {
        let out = ExportService.textReport(
            rows: [
                makeRow(ip: "10.0.0.1", hostname: "router", vendor: "Cisco", openPorts: [22, 80]),
                makeRow(ip: "10.0.0.2", hostname: nil, vendor: nil, openPorts: [])
            ],
            rangeInput: "10.0.0.0/24",
            scannedTotal: 2,
            aliveCount: 2
        )
        XCTAssertTrue(out.contains("10.0.0.1"))
        XCTAssertTrue(out.contains("router"))
        XCTAssertTrue(out.contains("Cisco"))
        XCTAssertTrue(out.contains("22, 80"))
        // Host with no ports shows em dash placeholder
        XCTAssertTrue(out.contains("10.0.0.2"))
    }

    func testJSONRoundtrip() throws {
        let original = [
            makeRow(
                ip: "10.0.0.1",
                label: "Router",
                hostname: "hgw",
                mac: "AA:BB",
                vendor: "Test",
                rttMs: 2.5,
                openPorts: [80, 443]
            )
        ]
        let data = try ExportService.json(rows: original)
        let decoded = try JSONDecoder().decode([ExportService.Row].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].ip, "10.0.0.1")
        XCTAssertEqual(decoded[0].label, "Router")
        XCTAssertEqual(decoded[0].openPorts, [80, 443])
    }

    // MARK: - CSV formula injection

    /// A hostname comes from the scanned host's own PTR record, so its owner chooses the string.
    /// This payload contains no comma, quote, or newline, so the RFC 4180 quoting rules leave it
    /// untouched — it reached the sheet verbatim and Excel executed it on open.
    func testCSVNeutralizesFormulaInHostname() {
        let csv = ExportService.csv(rows: [makeRow(hostname: "=cmd|'/c calc'!A1")])
        XCTAssertTrue(csv.contains("\"'=cmd|'/c calc'!A1\""), "got: \(csv)")
        XCTAssertFalse(csv.contains(",=cmd"), "formula must not start a cell")
    }

    func testCSVNeutralizesAllFormulaTriggers() {
        for trigger in ["=", "+", "-", "@", "\t", "\r"] {
            let csv = ExportService.csv(rows: [makeRow(vendor: "\(trigger)EVIL()")])
            XCTAssertTrue(
                csv.contains("\"'\(trigger)EVIL()\""),
                "trigger \(trigger.debugDescription) not neutralized: \(csv)"
            )
        }
    }

    func testCSVLeavesOrdinaryValuesUnquoted() {
        let csv = ExportService.csv(rows: [makeRow(hostname: "router.local", vendor: "Acme")])
        XCTAssertTrue(csv.contains(",router.local,"))
        XCTAssertFalse(csv.contains("'router.local"))
    }

    /// A negative RTT would render as `-2.5`, but numeric columns bypass `escape`, so guard that
    /// the neutralization did not start quoting ordinary numbers.
    func testCSVDoesNotQuoteNumericColumns() {
        let csv = ExportService.csv(rows: [makeRow(rttMs: 2.5, ttl: 64)])
        XCTAssertTrue(csv.contains(",2.5,64,"))
    }
}
