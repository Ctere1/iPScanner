import Foundation

/// Names the files iPScanner writes.
///
/// Exports and snapshots each built their own `DateFormatter` with the same format string and the
/// same `iPScanner-` prefix, so the two agreed only by coincidence — and a `DateFormatter` with a
/// fixed format and no explicit locale silently follows the user's calendar, which is how a
/// Buddhist- or Persian-calendar user gets `iPScanner-2569-07-17-1432.csv`. Locale is pinned here,
/// once.
enum ExportNaming {
    static let prefix = "iPScanner-"
    static let fileTimestampFormat = "yyyy-MM-dd-HHmm"
    static let reportTimestampFormat = "yyyy-MM-dd HH:mm"

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    /// `iPScanner-2026-07-17-1432.csv`
    static func fileName(ext: String, date: Date = Date()) -> String {
        "\(prefix)\(formatter(fileTimestampFormat).string(from: date)).\(ext)"
    }

    /// `2026-07-17 14:32` — the header line of a text report.
    static func reportTimestamp(_ date: Date = Date()) -> String {
        formatter(reportTimestampFormat).string(from: date)
    }
}
