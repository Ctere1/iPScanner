import Foundation
@testable import iPScanner

/// A `Scheduling` whose clock only moves when a test says so.
///
/// The real one is `Timer.scheduledTimer`, and the shortest auto-rescan interval the app offers is
/// 30 seconds — so testing the rescan rules for real meant sleeping for half a minute per case.
@MainActor
final class FakeScheduler: Scheduling {
    private(set) var now: Date

    private final class Work: ScheduledWork {
        let fireAt: Date
        let interval: TimeInterval
        let repeats: Bool
        let body: @MainActor () -> Void
        var cancelled = false

        init(fireAt: Date, interval: TimeInterval, repeats: Bool, body: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.interval = interval
            self.repeats = repeats
            self.body = body
        }

        func cancel() { cancelled = true }
    }

    private var scheduled: [Work] = []

    /// How many timers are live. A leak shows up here as a count that never falls.
    var pendingCount: Int { scheduled.filter { !$0.cancelled }.count }

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    func repeating(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        _ body: @escaping @MainActor () -> Void
    ) -> ScheduledWork {
        let work = Work(fireAt: now.addingTimeInterval(interval), interval: interval, repeats: true, body: body)
        scheduled.append(work)
        return work
    }

    func after(_ interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> ScheduledWork {
        let work = Work(fireAt: now.addingTimeInterval(interval), interval: interval, repeats: false, body: body)
        scheduled.append(work)
        return work
    }

    /// Moves the clock forward, firing anything that comes due on the way.
    func advance(by interval: TimeInterval) {
        let target = now.addingTimeInterval(interval)
        while let next = scheduled
            .filter({ !$0.cancelled && $0.fireAt <= target })
            .min(by: { $0.fireAt < $1.fireAt }) {
            now = next.fireAt
            if next.repeats {
                // Re-arm before firing: the body may inspect what is pending.
                scheduled.removeAll { $0 === next }
                scheduled.append(Work(
                    fireAt: next.fireAt.addingTimeInterval(next.interval),
                    interval: next.interval,
                    repeats: true,
                    body: next.body
                ))
            } else {
                scheduled.removeAll { $0 === next }
            }
            next.body()
        }
        now = target
    }
}
