import Foundation

extension String {
    /// Trims whitespace *and* newlines — the right rule for a value a human typed or a banner sent.
    ///
    /// Deliberately not applied to the parsers (ScanRange, PortScanner, TargetFileParser). They
    /// trim `.whitespaces` only, because they split on newlines first and a newline is a separator
    /// there, not padding. The two rules read almost identically and are not interchangeable, so
    /// this covers the user-input half and leaves the parsing half explicit at its call sites.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
