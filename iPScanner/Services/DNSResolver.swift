import Foundation
import Darwin

enum DNSResolver {
    private static let queue = DispatchQueue(
        label: "iPScanner.dns",
        qos: .utility,
        attributes: .concurrent
    )

    /// Races a reverse-DNS lookup against a timeout WITHOUT a structured task
    /// group. `rawLookup` wraps a blocking, non-cancellable `getnameinfo()` call
    /// (Darwin has no cancellable variant); if it ran as a task-group child,
    /// `withTaskGroup` would still await it to completion before returning even
    /// after the timeout task "wins" and `cancelAll()` is called — Swift's
    /// structured concurrency rules await every child before the group scope
    /// exits, regardless of cancellation. Unstructured `Task {}` has no such
    /// rule: this function returns the instant either side calls `state.fire`,
    /// leaving a slow lookup to finish on its own time and discard its result.
    static func reverseLookup(_ ip: String, timeout: Duration = .seconds(1)) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let state = ResumeOnce()

            Task {
                let result = await rawLookup(ip)
                state.fire { continuation.resume(returning: result) }
            }

            Task {
                try? await Task.sleep(for: timeout)
                state.fire { continuation.resume(returning: nil) }
            }
        }
    }

    private static func rawLookup(_ ip: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            queue.async {
                var sin = sockaddr_in()
                sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                sin.sin_family = sa_family_t(AF_INET)
                guard inet_pton(AF_INET, ip, &sin.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = withUnsafePointer(to: &sin) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        getnameinfo(sockaddrPtr,
                                    socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &hostBuf, socklen_t(NI_MAXHOST),
                                    nil, 0, NI_NAMEREQD)
                    }
                }
                if rc == 0 {
                    let host = String(cString: hostBuf)
                    continuation.resume(returning: host.isEmpty ? nil : host)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
