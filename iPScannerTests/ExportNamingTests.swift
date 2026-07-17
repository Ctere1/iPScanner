import XCTest
@testable import iPScanner

final class ExportNamingTests: XCTestCase {

    /// 2026-07-17 14:32:05 UTC, pinned so these assertions do not depend on when they run.
    private let fixed = Date(timeIntervalSince1970: 1_784_298_725)

    private func inUTC(_ body: () -> Void) {
        // The formatter uses the current time zone by design (a report timestamp should read in
        // local time); these tests pin it so the expected strings are stable.
        let original = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "UTC")!
        defer { NSTimeZone.default = original }
        body()
    }

    func testFileNameShape() {
        inUTC {
            XCTAssertEqual(ExportNaming.fileName(ext: "csv", date: fixed), "iPScanner-2026-07-17-1432.csv")
        }
    }

    func testSnapshotUsesCompoundExtension() {
        inUTC {
            XCTAssertEqual(
                ExportNaming.fileName(ext: "ipscan.json", date: fixed),
                "iPScanner-2026-07-17-1432.ipscan.json"
            )
        }
    }

    func testReportTimestampShape() {
        inUTC {
            XCTAssertEqual(ExportNaming.reportTimestamp(fixed), "2026-07-17 14:32")
        }
    }

    /// Guards the reason locale is pinned to en_US_POSIX: a DateFormatter with a fixed format and
    /// no explicit locale follows the user's calendar, so a Buddhist-calendar user would silently
    /// have got `iPScanner-2569-07-17-1432.csv`. `Locale.current` is read-only, so this asserts the
    /// year the Gregorian calendar produces rather than swapping the process locale.
    func testFileNameUsesGregorianYear() {
        inUTC {
            XCTAssertTrue(ExportNaming.fileName(ext: "csv", date: fixed).contains("2026"))
        }
    }

    func testExportAndSnapshotAgreeOnPrefix() {
        XCTAssertTrue(ExportService.defaultFileName(ext: "csv").hasPrefix(ExportNaming.prefix))
        XCTAssertTrue(SnapshotIO.defaultFileName().hasPrefix(ExportNaming.prefix))
    }
}
