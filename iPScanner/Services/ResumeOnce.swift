import Foundation

/// Guards a `CheckedContinuation` (or any single-fire callback) against being
/// resumed twice when two independent async sources race to produce a result
/// (e.g. a lookup vs. a timeout). Shared by `DNSResolver` and `NetBIOSResolver`.
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
