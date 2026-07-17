import Foundation

/// Guards a `CheckedContinuation` that several callback paths can reach — a probe that answers,
/// a connection that fails, and a timeout that fires can all race, and resuming twice traps.
/// The first caller wins; later ones are dropped.
final class ResumeOnce: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()

    func fire(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        block()
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`, for the GCD APIs that predate `Duration`.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
