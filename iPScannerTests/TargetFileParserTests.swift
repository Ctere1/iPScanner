import XCTest
@testable import iPScanner

final class TargetFileParserTests: XCTestCase {

    func testParsesIndividualIPs() throws {
        let result = try TargetFileParser.parse(text: """
        10.0.0.1
        10.0.0.2
        10.0.0.3
        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2", "10.0.0.3"])
        XCTAssertTrue(result.invalidLines.isEmpty)
        XCTAssertEqual(result.parsedTokenCount, 3)
    }

    func testParsesCIDR() throws {
        let result = try TargetFileParser.parse(text: "10.0.0.0/30")
        // /30 → 4 addresses, but ScanRange treats /30 as network+1 to broadcast-1 (2 hosts)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }

    func testParsesRange() throws {
        let result = try TargetFileParser.parse(text: "192.168.1.10-192.168.1.12")
        XCTAssertEqual(result.targets, ["192.168.1.10", "192.168.1.11", "192.168.1.12"])
    }

    func testParsesMixedTokensInLine() throws {
        let result = try TargetFileParser.parse(text: "10.0.0.1, 10.0.0.5-10.0.0.6, 192.168.1.0/30")
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5", "10.0.0.6", "192.168.1.1", "192.168.1.2"])
        XCTAssertEqual(result.parsedTokenCount, 3)
    }

    func testIgnoresBlankLinesAndComments() throws {
        let result = try TargetFileParser.parse(text: """

        # printers
        10.0.0.1

        # servers
        10.0.0.5

        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5"])
    }

    func testDeduplicatesAcrossLines() throws {
        let result = try TargetFileParser.parse(text: """
        10.0.0.1
        10.0.0.1
        10.0.0.0/30
        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }

    func testReportsInvalidLines() throws {
        let result = try TargetFileParser.parse(text: """
        10.0.0.1
        not-an-ip
        300.300.300.300
        10.0.0.5
        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5"])
        XCTAssertEqual(result.invalidLines.count, 2)
        XCTAssertEqual(result.invalidLines.map(\.content).sorted(), ["300.300.300.300", "not-an-ip"])
    }

    func testInvalidTokenInMixedLineDoesNotKillValidOnes() throws {
        let result = try TargetFileParser.parse(text: "10.0.0.1, not-valid, 10.0.0.5")
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5"])
        XCTAssertEqual(result.invalidLines.count, 1)
        XCTAssertEqual(result.invalidLines.first?.content, "not-valid")
    }

    func testEmptyTextReturnsNoTargets() throws {
        let result = try TargetFileParser.parse(text: "")
        XCTAssertTrue(result.targets.isEmpty)
        XCTAssertTrue(result.invalidLines.isEmpty)
    }

    func testCarriageReturnLineEndings() throws {
        // Windows-saved files use CRLF
        let result = try TargetFileParser.parse(text: "10.0.0.1\r\n10.0.0.2\r\n")
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }

    // MARK: - Size cap

    /// A shared or downloaded target list is untrusted input; one `0.0.0.0/0` line previously
    /// expanded 4.3 billion addresses with no cap at all in this parser.
    func testRejectsOversizedRangeWithoutExpanding() {
        let start = Date()
        XCTAssertThrowsError(try TargetFileParser.parse(text: "0.0.0.0/0")) { error in
            guard case TargetFileParser.ParseError.tooLarge = error else {
                return XCTFail("expected .tooLarge, got \(error)")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "rejection must not expand the range")
    }

    func testRejectsWhenAccumulatedTokensExceedLimit() {
        let text = (1...20).map { "10.0.\($0).0/24" }.joined(separator: "\n")  // ~5,080 hosts
        XCTAssertThrowsError(try TargetFileParser.parse(text: text, limit: 100))
    }

    func testAcceptsListAtLimit() throws {
        let result = try TargetFileParser.parse(text: "10.0.0.1, 10.0.0.2", limit: 2)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }
}
