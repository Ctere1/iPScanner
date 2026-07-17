import Foundation

/// A cancellable piece of scheduled work.
protocol ScheduledWork {
    func cancel()
}

/// Somewhere for timers to come from.
///
/// ScanController reached for `Timer.scheduledTimer` directly, which made the elapsed clock and the
/// auto-rescan interval untestable: verifying "a rescan fires when the interval elapses" meant
/// actually sleeping for the interval, and the shortest one on offer is 30 seconds. A fake
/// implementation lets the tests step time instead.
@MainActor
protocol Scheduling {
    /// Repeating work. `tolerance` lets the system coalesce the wakeup with other work.
    func repeating(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        _ body: @escaping @MainActor () -> Void
    ) -> ScheduledWork

    /// One-shot work.
    func after(_ interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> ScheduledWork

    var now: Date { get }
}

// MARK: - Live

@MainActor
struct TimerScheduler: Scheduling {
    var now: Date { Date() }

    func repeating(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        _ body: @escaping @MainActor () -> Void
    ) -> ScheduledWork {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in body() }
        }
        timer.tolerance = tolerance
        return TimerWork(timer)
    }

    func after(_ interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> ScheduledWork {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in body() }
        }
        return TimerWork(timer)
    }

    private struct TimerWork: ScheduledWork {
        private let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}
