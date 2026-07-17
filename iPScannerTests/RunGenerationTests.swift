import XCTest
@testable import iPScanner

/// The rule that keeps a superseded port scan from corrupting the run that replaced it. It was
/// three bare `generation != portScanGeneration` comparisons inside an untested controller.
final class RunGenerationTests: XCTestCase {

    func testAFreshTokenIsCurrent() {
        var gen = RunGeneration()
        let token = gen.begin()
        XCTAssertTrue(gen.isCurrent(token))
    }

    func testStartingANewRunRetiresThePreviousOne() {
        var gen = RunGeneration()
        let first = gen.begin()
        let second = gen.begin()
        XCTAssertFalse(gen.isCurrent(first), "the superseded run must not write its results")
        XCTAssertTrue(gen.isCurrent(second))
    }

    func testRetireInvalidatesTheInFlightRun() {
        var gen = RunGeneration()
        let token = gen.begin()
        gen.retire()
        XCTAssertFalse(gen.isCurrent(token), "a cancelled run's writebacks must become no-ops")
    }

    /// The subtle half, and the reason this is not just a Bool: an old run finishing late must not
    /// clear the flags of the run that replaced it.
    func testALateFinishingOldRunCannotClaimToBeCurrent() {
        var gen = RunGeneration()
        let old = gen.begin()
        let new = gen.begin()      // user restarts the scan
        // ...old run's task group finally drains here:
        XCTAssertFalse(gen.isCurrent(old), "the old run must not clear the new run's progress flags")
        XCTAssertTrue(gen.isCurrent(new), "the new run is untouched by the old one finishing")
    }

    func testCancelThenRestartLeavesOnlyTheRestartCurrent() {
        var gen = RunGeneration()
        let first = gen.begin()
        gen.retire()               // cancelPortScan()
        let second = gen.begin()   // runPortScan() again
        XCTAssertFalse(gen.isCurrent(first))
        XCTAssertTrue(gen.isCurrent(second))
    }

    func testTokensAreNotReused() {
        var gen = RunGeneration()
        var seen = Set<UInt64>()
        for _ in 0..<100 {
            let token = gen.begin()
            XCTAssertFalse(seen.contains(token), "a reused token would resurrect a retired run")
            seen.insert(token)
        }
    }

    func testAnUnstartedGenerationHasNoCurrentToken() {
        let gen = RunGeneration()
        XCTAssertFalse(gen.isCurrent(1), "nothing is in flight before the first begin()")
    }
}
