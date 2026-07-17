import Foundation

/// Turns a typed range string into the addresses to scan.
///
/// The GUI and the CLI both did this: parse, reject a bad chunk, expand, refuse an oversized list.
/// Only the wording of the refusal differed — the GUI offers examples, the CLI quotes the input —
/// so the decision is shared here and each caller phrases its own message.
enum TargetResolver {
    enum Outcome: Equatable {
        case targets([String])
        /// A chunk of a comma-separated list did not parse. `index` is 1-based, as shown to users.
        case invalidChunk(index: Int)
        /// Parsed cleanly but named nothing.
        case empty
        /// Rejected before expansion — `span` addresses against a `limit`.
        case tooLarge(span: Int, limit: Int)
    }

    static func resolve(range: String) -> Outcome {
        let parsed = ScanRange.parseAll(range)
        if let badIdx = parsed.firstInvalidIndex {
            return .invalidChunk(index: badIdx)
        }
        guard !parsed.ranges.isEmpty else {
            return .empty
        }
        // Rejects oversized input before expansion; a file's targets are capped by TargetFileParser.
        guard let expanded = ScanRange.uniqueAddresses(parsed.ranges) else {
            return .tooLarge(span: ScanRange.totalHostCount(parsed.ranges), limit: ScanRange.maxTargets)
        }
        guard !expanded.isEmpty else {
            return .empty
        }
        return .targets(expanded)
    }
}
