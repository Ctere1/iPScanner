import Foundation
import Darwin

/// ICMP echo over an unprivileged datagram socket.
///
/// Replaces spawning `/sbin/ping` per host. A fork/exec costs milliseconds of kernel work and its
/// two blocking reads park a dispatch thread for the whole timeout; at 32 concurrent probes that
/// saturated the 64-thread pool while the rest of the scan queued behind it. Here the socket is
/// non-blocking and the reply arrives on a DispatchSource, so a probe in flight holds a file
/// descriptor and nothing else.
///
/// `SOCK_DGRAM` + `IPPROTO_ICMP` needs no root on macOS: the kernel owns the echo identifier and
/// only delivers matching replies back to the socket that sent them.
enum ICMPPing {
    /// Shared by every in-flight probe: the work is a few bytes of packet handling per reply, and
    /// a queue per probe would defeat the point of not spawning threads.
    private static let queue = DispatchQueue(label: "iPScanner.icmp", qos: .userInitiated)

    static func ping(_ ip: String, timeoutMs: Int) async -> DiscoverResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<DiscoverResult?, Never>) in
            queue.async {
                start(ip: ip, timeoutMs: timeoutMs, continuation: continuation)
            }
        }
    }

    /// True when the kernel lets this process open an ICMP socket at all. A sandbox without the
    /// network-client entitlement, or a hardened configuration, can refuse it — the caller then
    /// falls back to `/sbin/ping`. Probed once; the answer cannot change while the app runs.
    static let isAvailable: Bool = {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }()

    private static func start(
        ip: String,
        timeoutMs: Int,
        continuation: CheckedContinuation<DiscoverResult?, Never>
    ) {
        let state = ResumeOnce()

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else {
            state.fire { continuation.resume(returning: nil) }
            return
        }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            state.fire { continuation.resume(returning: nil) }
            return
        }
        // Non-blocking: the DispatchSource tells us when a reply is readable, so recv never waits.
        // Bail rather than continue on failure — a blocking socket here would park the shared queue
        // inside recv and stall every other probe behind it.
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            close(fd)
            state.fire { continuation.resume(returning: nil) }
            return
        }

        // The kernel rewrites the echo id on SOCK_DGRAM sockets, so the token in the payload — not
        // the id — is what proves a reply belongs to this probe.
        let token = UInt32.random(in: .min ... .max)
        let packet = echoRequest(token: token)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let timeoutWork = DispatchWorkItem {
            state.fire {
                source.cancel()
                continuation.resume(returning: nil)
            }
        }

        // The cancel handler is the single owner of the fd: every exit path cancels the source, so
        // the descriptor is closed exactly once whether we time out, fail, or get a reply.
        source.setCancelHandler {
            timeoutWork.cancel()
            close(fd)
        }

        let sentAt = Date()
        source.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 1024)
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else {
                // EAGAIN on a spurious wakeup: keep waiting for the real reply or the timeout.
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                state.fire {
                    source.cancel()
                    continuation.resume(returning: nil)
                }
                return
            }
            guard let reply = parseEchoReply(Array(buf[0..<n]), expecting: token) else { return }
            let rtt = Date().timeIntervalSince(sentAt) * 1000
            state.fire {
                source.cancel()
                continuation.resume(returning: DiscoverResult(rttMs: rtt, ttl: reply.ttl))
            }
        }
        source.resume()

        let sent = withUnsafePointer(to: &addr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                sendto(fd, packet, packet.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else {
            // No route to the host, or the network is down: nothing will ever arrive.
            state.fire {
                source.cancel()
                continuation.resume(returning: nil)
            }
            return
        }

        queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeoutWork)
    }

    // MARK: - Wire format

    /// ICMP echo request: type 8, code 0, checksum, identifier, sequence, then the token payload.
    /// Written byte-at-a-time in network order rather than by copying a struct, so it does not
    /// depend on the host's endianness or struct padding.
    static func echoRequest(token: UInt32) -> [UInt8] {
        var packet: [UInt8] = [
            8, 0,        // type = echo request, code = 0
            0, 0,        // checksum, filled in below
            0, 0,        // identifier — the kernel overwrites this on SOCK_DGRAM
            0, 1         // sequence
        ]
        packet += Array("iPScan".utf8)
        packet += [
            UInt8(truncatingIfNeeded: token >> 24),
            UInt8(truncatingIfNeeded: token >> 16),
            UInt8(truncatingIfNeeded: token >> 8),
            UInt8(truncatingIfNeeded: token)
        ]
        let sum = checksum(packet)
        packet[2] = UInt8(truncatingIfNeeded: sum >> 8)
        packet[3] = UInt8(truncatingIfNeeded: sum)
        return packet
    }

    /// Standard RFC 1071 one's-complement sum over the packet, treated as big-endian 16-bit words.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum &+= UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum &+= UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) &+ (sum >> 16) }
        return UInt16(truncatingIfNeeded: ~sum)
    }

    struct EchoReply: Equatable {
        let ttl: Int
    }

    /// Parses a reply, which arrives with its IPv4 header attached. Returns nil unless this is an
    /// echo reply carrying our own token — every read is bounds-checked, because the bytes come
    /// from the network and a malformed or truncated packet must not trap.
    static func parseEchoReply(_ bytes: [UInt8], expecting token: UInt32) -> EchoReply? {
        guard bytes.count >= 20 else { return nil }
        let version = bytes[0] >> 4
        guard version == 4 else { return nil }
        let headerLength = Int(bytes[0] & 0x0F) * 4
        guard headerLength >= 20, bytes.count >= headerLength + 8 else { return nil }

        let ttl = Int(bytes[8])
        let icmp = bytes[headerLength...]
        guard icmp.first == 0 else { return nil }   // type 0 = echo reply; 3/11 are errors

        let payload = bytes[(headerLength + 8)...]
        guard payload.count >= 10 else { return nil }
        let expected: [UInt8] = Array("iPScan".utf8) + [
            UInt8(truncatingIfNeeded: token >> 24),
            UInt8(truncatingIfNeeded: token >> 16),
            UInt8(truncatingIfNeeded: token >> 8),
            UInt8(truncatingIfNeeded: token)
        ]
        guard Array(payload.prefix(expected.count)) == expected else { return nil }
        return EchoReply(ttl: ttl)
    }
}
