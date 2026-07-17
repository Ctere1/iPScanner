import XCTest
@testable import iPScanner

/// Auto-rescan timing, tested without waiting out a real timer.
@MainActor
final class RescanSchedulerTests: XCTestCase {

    func testFiresWhenTheIntervalElapses() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)
        var fired = 0

        scheduler.schedule(after: 30) { fired += 1 }
        XCTAssertEqual(fired, 0, "must not fire early")

        clock.advance(by: 29)
        XCTAssertEqual(fired, 0)

        clock.advance(by: 1)
        XCTAssertEqual(fired, 1)
    }

    func testFiresOnlyOnce() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)
        var fired = 0

        scheduler.schedule(after: 30) { fired += 1 }
        clock.advance(by: 300)
        XCTAssertEqual(fired, 1, "a rescan is one-shot; the next one is scheduled by the scan itself")
    }

    func testPublishesWhenTheNextRescanIsDue() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)

        XCTAssertNil(scheduler.nextRescanAt)
        scheduler.schedule(after: 60) {}
        XCTAssertEqual(scheduler.nextRescanAt, clock.now.addingTimeInterval(60))
        XCTAssertTrue(scheduler.isScheduled)
    }

    func testCancelPreventsTheFire() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)
        var fired = 0

        scheduler.schedule(after: 30) { fired += 1 }
        scheduler.cancel()
        clock.advance(by: 300)

        XCTAssertEqual(fired, 0)
        XCTAssertNil(scheduler.nextRescanAt)
        XCTAssertFalse(scheduler.isScheduled)
    }

    /// Changing the interval must not leave the old timer armed as well.
    func testReschedulingReplacesThePendingTimer() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)
        var fired = 0

        scheduler.schedule(after: 30) { fired += 1 }
        scheduler.schedule(after: 60) { fired += 1 }
        XCTAssertEqual(clock.pendingCount, 1, "the first timer must have been cancelled")

        clock.advance(by: 30)
        XCTAssertEqual(fired, 0, "the replaced timer must not fire at its old deadline")

        clock.advance(by: 30)
        XCTAssertEqual(fired, 1)
    }

    /// The callback typically starts a scan, which schedules the next rescan. Clearing the
    /// bookkeeping after the callback would wipe that new schedule.
    func testCallbackMayScheduleTheNextRescan() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)
        var fired = 0

        func arm() {
            scheduler.schedule(after: 30) {
                fired += 1
                arm()
            }
        }
        arm()

        clock.advance(by: 30)
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(scheduler.isScheduled, "the rescan scheduled from inside the callback survives")

        clock.advance(by: 30)
        XCTAssertEqual(fired, 2, "and it fires")
    }

    func testStateIsClearedOnceItHasFired() {
        let clock = FakeScheduler()
        let scheduler = RescanScheduler(scheduler: clock)

        scheduler.schedule(after: 30) {}
        clock.advance(by: 30)

        XCTAssertNil(scheduler.nextRescanAt, "nothing is pending once it has fired")
        XCTAssertFalse(scheduler.isScheduled)
    }
}
