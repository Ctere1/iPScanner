import XCTest
@testable import iPScanner

/// Splitting the Process boilerplate out of ARPLookup and NetworkScanner made all three testable
/// for the first time — the parsers because they no longer need a subprocess, the runner because
/// it is now one thing rather than two copies.
final class SubprocessTests: XCTestCase {

    func testCapturesStdout() async {
        let result = await Subprocess.text("/bin/echo", ["hello"])
        XCTAssertEqual(result?.status, 0)
        XCTAssertEqual(result?.output.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    /// A non-zero exit is a normal answer (an unreachable host), not a failure to run.
    func testNonZeroExitIsReportedNotSwallowed() async {
        let result = await Subprocess.run("/usr/bin/false", [])
        XCTAssertNotNil(result, "the binary ran; it just exited non-zero")
        XCTAssertNotEqual(result?.status, 0)
    }

    /// Distinct from the above: nil means the binary could not be launched at all.
    func testMissingBinaryReturnsNil() async {
        let result = await Subprocess.run("/nonexistent/definitely-not-here", [])
        XCTAssertNil(result)
    }

    /// The reason stderr goes to nullDevice: an undrained pipe deadlocks the child once it fills.
    func testStderrHeavyChildDoesNotDeadlock() async {
        let script = "for i in $(seq 1 2000); do echo error line $i >&2; done; echo done"
        let result = await Subprocess.text("/bin/sh", ["-c", script])
        XCTAssertEqual(result?.status, 0)
        XCTAssertEqual(result?.output.trimmingCharacters(in: .whitespacesAndNewlines), "done")
    }

    func testLargeStdoutIsReadFully() async {
        let result = await Subprocess.text("/bin/sh", ["-c", "seq 1 20000"])
        XCTAssertEqual(result?.status, 0)
        let lines = result?.output.split(separator: "\n") ?? []
        XCTAssertEqual(lines.count, 20000)
        XCTAssertEqual(lines.last, "20000")
    }
}
