import XCTest
@testable import iPScanner

/// First tests for the scan lifecycle. It was untestable by construction: `start()` built its own
/// NetworkScanner, so reaching this code meant scanning a real subnet.
@MainActor
final class ScanLifecycleTests: XCTestCase {

    private func makeController(
        _ name: String = #function,
        scanner: FakeScanner,
        clock: FakeScheduler? = nil
    ) -> ScanController {
        let suite = "ScanLifecycleTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        return ScanController(
            labelStore: LabelStore(store: PersistedStore(defaults: defaults)),
            savedRangeStore: SavedRangeStore(store: PersistedStore(defaults: defaults)),
            scheduler: clock ?? FakeScheduler(),
            makeScanner: { _ in scanner }
        )
    }

    /// Drives the controller's scan task to completion.
    private func runScan(_ controller: ScanController) async {
        controller.start()
        for _ in 0..<200 where controller.isScanning {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Happy path

    func testScanCollectsHostsAndFinishes() async {
        let controller = makeController(scanner: .allAlive(["10.0.0.1", "10.0.0.2"]))
        controller.rangeInput = "10.0.0.1-10.0.0.2"
        await runScan(controller)

        XCTAssertEqual(controller.hosts.count, 2)
        XCTAssertEqual(controller.aliveCount, 2)
        XCTAssertEqual(controller.state, .done(scanned: 2, total: 2))
        XCTAssertFalse(controller.isScanning)
    }

    func testHostEventsForTheSameIPMergeIntoOneRow() async {
        let scanner = FakeScanner([
            .host(iPScanner.Host(ip: "10.0.0.1", rttMs: 1.0, ttl: 64, status: .alive)),
            .host(iPScanner.Host(ip: "10.0.0.1", hostname: "nas.local", mac: "aa:bb:cc:dd:ee:ff", status: .alive)),
            .done
        ])
        let controller = makeController(scanner: scanner)
        controller.rangeInput = "10.0.0.1"
        await runScan(controller)

        XCTAssertEqual(controller.hosts.count, 1, "enrichment must not add a second row")
        XCTAssertEqual(controller.hosts[0].hostname, "nas.local")
        XCTAssertEqual(controller.hosts[0].rttMs, 1.0, "the discovery event's rtt survives enrichment")
    }

    func testDeadHostsAreRecordedButNotCounted() async {
        let scanner = FakeScanner([
            .host(iPScanner.Host(ip: "10.0.0.1", status: .alive)),
            .host(iPScanner.Host(ip: "10.0.0.2", status: .dead)),
            .done
        ])
        let controller = makeController(scanner: scanner)
        controller.rangeInput = "10.0.0.1-10.0.0.2"
        await runScan(controller)

        XCTAssertEqual(controller.hosts.count, 2)
        XCTAssertEqual(controller.aliveCount, 1)
        XCTAssertEqual(controller.filteredHosts.count, 1, "dead hosts are hidden by default")
    }

    // MARK: - Input refusals

    func testInvalidRangeIsRefusedBeforeScanning() async {
        let controller = makeController(scanner: .allAlive([]))
        controller.rangeInput = "not-an-ip"
        controller.start()

        XCTAssertFalse(controller.isScanning)
        XCTAssertNotNil(controller.lastError)
        XCTAssertTrue(controller.hosts.isEmpty)
    }

    func testEmptyRangeIsRefused() async {
        let controller = makeController(scanner: .allAlive([]))
        controller.rangeInput = ""
        controller.start()
        XCTAssertNotNil(controller.lastError)
        XCTAssertEqual(controller.state, .idle)
    }

    func testStartingClearsThePreviousError() async {
        let controller = makeController(scanner: .allAlive(["10.0.0.1"]))
        controller.rangeInput = "garbage"
        controller.start()
        XCTAssertNotNil(controller.lastError)

        controller.rangeInput = "10.0.0.1"
        await runScan(controller)
        XCTAssertNil(controller.lastError)
    }

    // MARK: - Restart

    /// A second scan replaces the first one's results rather than appending to them.
    func testRestartingClearsThePreviousHosts() async {
        let controller = makeController(scanner: .allAlive(["10.0.0.1", "10.0.0.2"]))
        controller.rangeInput = "10.0.0.1-10.0.0.2"
        await runScan(controller)
        XCTAssertEqual(controller.hosts.count, 2)

        await runScan(controller)
        XCTAssertEqual(controller.hosts.count, 2, "a rescan replaces rather than accumulates")
    }

    func testStartIsIgnoredWhileAScanIsRunning() async {
        var scanner = FakeScanner.allAlive(["10.0.0.1"])
        scanner.stepNanoseconds = 20_000_000
        let controller = makeController(scanner: scanner)
        controller.rangeInput = "10.0.0.1"

        controller.start()
        XCTAssertTrue(controller.isScanning)
        controller.start()   // must be a no-op, not a second run
        await runScan(controller)

        XCTAssertEqual(controller.hosts.count, 1)
    }

    // MARK: - Warnings

    func testDuplicateWarningsAreMergedNotRepeated() async {
        let scanner = FakeScanner([.warning(.arpEmpty), .warning(.arpEmpty), .done])
        let controller = makeController(scanner: scanner)
        controller.rangeInput = "10.0.0.1"
        await runScan(controller)

        XCTAssertEqual(controller.warnings.count, 1, "the same warning twice is still one warning")
    }

    func testBannerFailureCountsAccumulate() async {
        let scanner = FakeScanner([
            .warning(.bannerFetchFailures(count: 2)),
            .warning(.bannerFetchFailures(count: 3)),
            .done
        ])
        let controller = makeController(scanner: scanner)
        controller.rangeInput = "10.0.0.1"
        await runScan(controller)

        XCTAssertEqual(controller.warnings.count, 1)
        guard case .bannerFetchFailures(let count) = controller.warnings[0] else {
            return XCTFail("expected a banner-failure warning")
        }
        XCTAssertEqual(count, 5, "counts add up rather than the last one winning")
    }

    func testWarningsAreClearedOnRestart() async {
        let scanner = FakeScanner([.warning(.arpEmpty), .done])
        let controller = makeController(scanner: scanner)
        controller.rangeInput = "10.0.0.1"
        await runScan(controller)
        XCTAssertEqual(controller.warnings.count, 1)

        await runScan(controller)
        XCTAssertEqual(controller.warnings.count, 1, "not two — a new run starts from a clean slate")
    }

    // MARK: - Auto-rescan

    func testRescanIsScheduledWhenTheScanFinishes() async {
        let clock = FakeScheduler()
        let controller = makeController(scanner: .allAlive(["10.0.0.1"]), clock: clock)
        controller.rangeInput = "10.0.0.1"
        controller.rescanInterval = .s30
        await runScan(controller)

        XCTAssertNotNil(controller.nextRescanAt, "a finished scan arms the next one")
    }

    func testNoRescanIsScheduledWhenTheIntervalIsOff() async {
        let controller = makeController(scanner: .allAlive(["10.0.0.1"]))
        controller.rangeInput = "10.0.0.1"
        controller.rescanInterval = .off
        await runScan(controller)

        XCTAssertNil(controller.nextRescanAt)
    }

    func testStoppingCancelsThePendingRescan() async {
        let controller = makeController(scanner: .allAlive(["10.0.0.1"]))
        controller.rangeInput = "10.0.0.1"
        controller.rescanInterval = .s30
        await runScan(controller)
        XCTAssertNotNil(controller.nextRescanAt)

        controller.stop()
        XCTAssertNil(controller.nextRescanAt, "Stop means stop, including the automatic next one")
    }
}
