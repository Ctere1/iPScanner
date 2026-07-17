import Foundation
import Observation

/// Fires a callback once, `interval` from now, and publishes when that will be.
///
/// Split out of ScanController so the auto-rescan rules can be tested without waiting out a real
/// 30-second timer. `nextRescanAt` is published because the status bar counts down to it.
@Observable
@MainActor
final class RescanScheduler {
    @ObservationIgnored private let scheduler: Scheduling
    @ObservationIgnored private var work: ScheduledWork?

    /// When the next rescan is due, or nil if none is scheduled.
    private(set) var nextRescanAt: Date?

    var isScheduled: Bool { nextRescanAt != nil }

    init(scheduler: Scheduling? = nil) {
        // Built here rather than as a default argument: a default argument is evaluated in the
        // caller's isolation, and TimerScheduler is @MainActor.
        self.scheduler = scheduler ?? TimerScheduler()
    }

    /// Replaces any pending rescan with a fresh one.
    func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        cancel()
        nextRescanAt = scheduler.now.addingTimeInterval(interval)
        work = scheduler.after(interval) { [weak self] in
            guard let self else { return }
            // Cleared before the callback runs: it may start a scan, which schedules the next one,
            // and clearing afterwards would wipe that.
            self.work = nil
            self.nextRescanAt = nil
            body()
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
        nextRescanAt = nil
    }
}
