import Foundation

/// Retires superseded runs of a restartable async job.
///
/// A port scan can be cancelled or replaced while its tasks are still in flight. Those tasks must
/// not write their results, and — the subtler half — a finishing *old* run must not clear the
/// progress flags belonging to the *new* run that replaced it. Both reduce to one question: is the
/// token I started with still the current one?
///
/// Wraps on overflow deliberately: the counter only ever needs to compare unequal to the tokens
/// still in flight, and at one bump per scan a UInt64 will not get there anyway.
struct RunGeneration: Equatable, Sendable {
    private var current: UInt64 = 0

    /// Starts a run, retiring any previous one, and returns the new run's token.
    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    /// Retires the in-flight run without starting one: its writebacks become no-ops.
    mutating func retire() {
        current &+= 1
    }

    /// Whether `token` names the run that is current now.
    func isCurrent(_ token: UInt64) -> Bool {
        current == token
    }
}
