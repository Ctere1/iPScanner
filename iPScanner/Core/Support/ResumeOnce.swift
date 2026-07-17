import Foundation
import Network

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

/// ``ResumeOnce`` plus the connection teardown that every network probe pairs it with.
///
/// PortScanner, BannerProbe and WakeOnLAN each grew a private class that was this, byte for byte:
/// a lock, a `done` flag, and a `finish` that cancels the connection before resuming. Cancelling
/// matters as much as the guard — an uncancelled timeout block keeps the connection and its
/// continuation alive for the whole window even when the port answered in 2ms, and across a wide
/// scan that is a large rolling set of dead-but-retained connections.
final class ConnectionGate: @unchecked Sendable {
    private let once = ResumeOnce()
    private let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// Cancels the connection and runs `block` — the first caller wins, later ones are dropped.
    func finish(_ block: @escaping () -> Void) {
        once.fire { [connection] in
            connection.cancel()
            block()
        }
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`, for the GCD APIs that predate `Duration`.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
