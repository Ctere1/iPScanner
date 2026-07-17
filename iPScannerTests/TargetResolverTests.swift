import XCTest
@testable import iPScanner

/// The range→addresses decision, shared by the GUI's start() and the CLI's resolveTargets(). Each
/// phrases its own error; this pins the decision they both take.
final class TargetResolverTests: XCTestCase {

    private func targets(_ range: String) -> [String]? {
        if case .targets(let t) = TargetResolver.resolve(range: range) { return t }
        return nil
    }

    func testExpandsACIDR() {
        XCTAssertEqual(targets("10.0.0.0/30"), ["10.0.0.1", "10.0.0.2"])
    }

    func testExpandsAHyphenRange() {
        XCTAssertEqual(targets("10.0.0.5-10.0.0.7"), ["10.0.0.5", "10.0.0.6", "10.0.0.7"])
    }

    func testExpandsASingleAddress() {
        XCTAssertEqual(targets("10.0.0.5"), ["10.0.0.5"])
    }

    func testCombinesCommaSeparatedChunks() {
        XCTAssertEqual(targets("10.0.0.1, 10.0.0.2"), ["10.0.0.1", "10.0.0.2"])
    }

    func testDeduplicatesOverlappingChunks() {
        let result = targets("10.0.0.1-10.0.0.3, 10.0.0.2-10.0.0.4")
        XCTAssertEqual(result, ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4"])
    }

    // MARK: - Refusals

    func testReportsWhichChunkIsBad() {
        XCTAssertEqual(
            TargetResolver.resolve(range: "10.0.0.0/24, nonsense"),
            .invalidChunk(index: 2),
            "the index is what lets both callers point at the offending chunk"
        )
    }

    func testEmptyInput() {
        XCTAssertEqual(TargetResolver.resolve(range: ""), .empty)
        XCTAssertEqual(TargetResolver.resolve(range: "   "), .empty)
    }

    /// The cap is checked against the span *before* expanding — the point is not to allocate a
    /// four-billion-element array in order to discover it is too big.
    func testOversizedRangeIsRefusedWithItsSpan() {
        guard case .tooLarge(let span, let limit) = TargetResolver.resolve(range: "10.0.0.0/8") else {
            return XCTFail("a /8 must be refused")
        }
        XCTAssertEqual(limit, ScanRange.maxTargets)
        XCTAssertGreaterThan(span, limit)
    }

    func testARangeAtTheLimitIsAccepted() {
        // /22 is 1022 usable hosts — comfortably inside the cap, and a realistic office subnet.
        guard case .targets(let t) = TargetResolver.resolve(range: "10.0.0.0/22") else {
            return XCTFail("a /22 must be accepted")
        }
        XCTAssertEqual(t.count, 1022)
    }
}
