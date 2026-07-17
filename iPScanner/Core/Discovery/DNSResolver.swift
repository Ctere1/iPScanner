import Foundation
import Darwin

enum DNSResolver {
    private static let queue = DispatchQueue(
        label: "iPScanner.dns",
        qos: .utility,
        attributes: .concurrent
    )

    /// Reverse-resolves `ip`, giving up after `timeout`.
    ///
    /// The timeout can only free the *caller*: `getnameinfo` is a blocking syscall with no
    /// cancellation, so its worker thread stays parked until the resolver itself gives up. The
    /// previous implementation raced the lookup against a sleeping task inside a `withTaskGroup`,
    /// which could not even do that — a task group awaits every child before it returns, so
    /// `reverseLookup` always blocked for the full `getnameinfo` duration (up to ~30s against an
    /// unresponsive resolver) and then discarded the answer when the sleeper had won the race.
    static func reverseLookup(_ ip: String, timeout: Duration = .seconds(1)) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let state = ResumeOnce()

            let timeoutWork = DispatchWorkItem {
                state.fire { continuation.resume(returning: nil) }
            }
            queue.asyncAfter(deadline: .now() + timeout.timeInterval, execute: timeoutWork)

            queue.async {
                let name = blockingLookup(ip)
                timeoutWork.cancel()
                state.fire { continuation.resume(returning: name) }
            }
        }
    }

    /// Blocking reverse lookup. Must not run on the main thread or a cooperative-pool thread.
    private static func blockingLookup(_ ip: String) -> String? {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &sin.sin_addr) == 1 else { return nil }

        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = withUnsafePointer(to: &sin) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getnameinfo(sockaddrPtr,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostBuf, socklen_t(NI_MAXHOST),
                            nil, 0, NI_NAMEREQD)
            }
        }
        guard rc == 0 else { return nil }
        let host = String(cString: hostBuf)
        return host.isEmpty ? nil : host
    }
}
