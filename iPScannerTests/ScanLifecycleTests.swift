import XCTest
@testable import iPScanner

@MainActor
final class ScanLifecycleTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func stream(_ ip: String) -> AsyncStream<ScanEvent> {
        AsyncStream {
            $0.yield(.host(iPScanner.Host(ip: ip, status: .alive)))
            $0.yield(.progress(scanned: 1, total: 1))
            $0.yield(.done)
            $0.finish()
        }
    }

    func testDeepRunCompletesOnlyAfterBannersAndThenSchedulesRescan() async {
        let gate = BannerGate()
        var operations = ScanController.Operations()
        operations.scan = { [self] _, _ in stream("10.0.0.1") }
        operations.probe = { _, _ in [80] }
        operations.banner = { _, _ in await gate.read() }
        let controller = ScanController(operations: operations)
        defer { controller.stop() }
        controller.rangeInput = "10.0.0.1"
        controller.profile = .deep
        controller.rescanInterval = .s30
        controller.start()
        await waitUntil { controller.phase == .banners }
        XCTAssertTrue(controller.isScanning)
        XCTAssertNil(controller.nextRescanAt)
        await gate.release("Example")
        await waitUntil { !controller.isScanning }
        XCTAssertEqual(controller.state, .done(scanned: 1, total: 1))
        XCTAssertEqual(controller.hosts.first?.serviceTitle, "Example")
        XCTAssertEqual(controller.hosts.first?.openPorts, [80])
        XCTAssertNotNil(controller.nextRescanAt)
    }

    func testStopAndImmediateRestartRejectsOldDiscoveryEvents() async {
        var producers: [AsyncStream<ScanEvent>.Continuation] = []
        var operations = ScanController.Operations()
        operations.scan = { _, _ in AsyncStream { producers.append($0) } }
        let controller = ScanController(operations: operations)
        defer { controller.stop(); producers.forEach { $0.finish() } }
        controller.rangeInput = "10.0.0.1"
        controller.start()
        controller.stop()
        XCTAssertEqual(controller.state, .stopped(scanned: 0, total: 1))
        controller.rangeInput = "10.0.0.2"
        controller.start()
        producers[0].yield(.host(iPScanner.Host(ip: "10.0.0.1", status: .alive)))
        producers[0].yield(.done)
        producers[0].finish()
        producers[1].yield(.host(iPScanner.Host(ip: "10.0.0.2", status: .alive)))
        producers[1].yield(.progress(scanned: 1, total: 1))
        producers[1].finish()
        await waitUntil { !controller.isScanning }
        XCTAssertEqual(controller.hosts.map(\.ip), ["10.0.0.2"])
    }

    func testSnapshotLoadCancelsDeepPortsAndIgnoresLateResults() async {
        let gate = PortGate()
        var operations = ScanController.Operations()
        operations.scan = { [self] _, _ in stream("10.0.0.1") }
        operations.probe = { _, _ in await gate.read() }
        let controller = ScanController(operations: operations)
        defer { controller.stop() }
        controller.rangeInput = "10.0.0.1"
        controller.profile = .deep
        controller.rescanInterval = .s30
        controller.start()
        await waitUntil { controller.portScanInProgress }
        let snapshot = ScanSnapshot(version: 1, createdAt: Date(), rangeInput: "10.0.0.9",
                                    hosts: [], labels: [:])
        controller.applySnapshot(snapshot)
        await gate.release()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(controller.isScanning)
        XCTAssertFalse(controller.portScanInProgress)
        XCTAssertTrue(controller.hosts.isEmpty)
        XCTAssertEqual(controller.rangeInput, "10.0.0.9")
        XCTAssertNil(controller.nextRescanAt)
    }

    func testImportedTargetsCanRunAndScheduleRescanWithoutRangeText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "10.0.0.7".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var received: [String] = []
        var operations = ScanController.Operations()
        operations.scan = { [self] targets, _ in
            received = targets
            return stream(targets[0])
        }
        let controller = ScanController(operations: operations)
        defer { controller.stop() }
        try controller.loadImportedFile(url: url)
        controller.rescanInterval = .s30
        XCTAssertEqual(controller.rangeInput, "")
        XCTAssertTrue(controller.canStart)
        controller.start()
        await waitUntil { !controller.isScanning }
        XCTAssertEqual(received, ["10.0.0.7"])
        XCTAssertNotNil(controller.nextRescanAt)
    }

    func testStopDuringBannerDoesNotCompleteOrScheduleRescan() async {
        let gate = BannerGate()
        var operations = ScanController.Operations()
        operations.scan = { [self] _, _ in stream("10.0.0.1") }
        operations.probe = { _, _ in [80] }
        operations.banner = { _, _ in await gate.read() }
        let controller = ScanController(operations: operations)
        controller.rangeInput = "10.0.0.1"
        controller.profile = .deep
        controller.rescanInterval = .s30
        controller.start()
        await waitUntil { controller.phase == .banners }
        controller.stop()
        await gate.release("Stale banner")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.state, .stopped(scanned: 1, total: 1))
        XCTAssertNil(controller.hosts.first?.serviceTitle)
        XCTAssertNil(controller.nextRescanAt)
    }
}

private actor BannerGate {
    private var continuation: CheckedContinuation<String?, Never>?
    private var released = false
    private var value: String?
    func read() async -> String? {
        if released { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: String) {
        released = true
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
private actor PortGate {
    private var continuation: CheckedContinuation<[Int], Never>?
    private var released = false
    func read() async -> [Int] {
        if released { return [80] }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume(returning: [80])
        continuation = nil
    }
}
