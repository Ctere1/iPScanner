import XCTest
@testable import iPScanner

/// The six hand-rolled copies this helper replaced were never tested — including the one in
/// PortScanner that silently never checked for cancellation.
final class WindowedTaskGroupTests: XCTestCase {

    /// Tracks how many operations are running at once, and the high-water mark.
    private actor ConcurrencyTracker {
        private(set) var peak = 0
        private var current = 0

        func enter() {
            current += 1
            peak = max(peak, current)
        }

        func leave() {
            current -= 1
        }
    }

    func testRunsEveryItem() async {
        let results = await windowedMap(Array(1...50), limit: 4) { $0 * 2 }
        XCTAssertEqual(results.count, 50)
        XCTAssertEqual(results.sorted(), (1...50).map { $0 * 2 })
    }

    func testNeverExceedsLimit() async {
        let tracker = ConcurrencyTracker()
        _ = await windowedMap(Array(1...40), limit: 5) { _ -> Int in
            await tracker.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await tracker.leave()
            return 0
        }
        let peak = await tracker.peak
        XCTAssertLessThanOrEqual(peak, 5, "window exceeded its limit")
        XCTAssertGreaterThan(peak, 1, "work never actually ran concurrently")
    }

    func testLimitLargerThanItemCountIsFine() async {
        let results = await windowedMap([1, 2, 3], limit: 64) { $0 }
        XCTAssertEqual(results.sorted(), [1, 2, 3])
    }

    func testEmptyInput() async {
        let results = await windowedMap([Int](), limit: 4) { $0 }
        XCTAssertTrue(results.isEmpty)
    }

    func testZeroLimitDoesNothingRatherThanHang() async {
        let results = await windowedMap([1, 2, 3], limit: 0) { $0 }
        XCTAssertTrue(results.isEmpty)
    }

    /// The behaviour PortScanner's copy was missing: a caller that stops wants the remaining items
    /// never started, not merely ignored.
    func testOnEachReturningFalseStopsEarly() async {
        let started = ConcurrencyTracker()
        var seen = 0
        await withWindowedTaskGroup(
            over: Array(1...100),
            limit: 2,
            operation: { item -> Int in
                await started.enter()
                await started.leave()
                return item
            }
        ) { _ in
            seen += 1
            return seen < 3
        }
        XCTAssertEqual(seen, 3, "should have stopped after the third result")
    }

    func testResultsArriveEvenWhenOperationsFinishOutOfOrder() async {
        // Item 1 sleeps longest, so completion order is the reverse of input order.
        let results = await windowedMap([30, 20, 10], limit: 3) { ms -> Int in
            try? await Task.sleep(for: .milliseconds(ms))
            return ms
        }
        XCTAssertEqual(results.sorted(), [10, 20, 30])
    }
}
