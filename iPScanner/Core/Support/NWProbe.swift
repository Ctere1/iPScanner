import Foundation
import Network

/// The `NWConnection` scaffolding every probe in Discovery/ needs: build a connection, race a
/// timeout against the state handler, tear down on every terminal path exactly once.
///
/// Five probes had each written their own copy. They are not identical — a TCP connect scan only
/// cares whether the handshake completed, while a UDP query has to send and then read — but the
/// racing and teardown are the same, and that is the part that is easy to get subtly wrong.
enum NWProbe {
    /// True if a TCP handshake to `ip:port` completes within `timeoutMs`.
    static func canConnect(_ ip: String, port: UInt16, timeoutMs: Int) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: nwPort)
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue.global(qos: .userInitiated)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = ConnectionGate(connection)
            let timeoutWork = DispatchWorkItem { gate.finish { continuation.resume(returning: false) } }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    timeoutWork.cancel()
                    gate.finish { continuation.resume(returning: true) }
                case .failed, .cancelled:
                    timeoutWork.cancel()
                    gate.finish { continuation.resume(returning: false) }
                case .setup, .preparing, .waiting:
                    break
                @unknown default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeoutWork)
            connection.start(queue: queue)
        }
    }

    /// Sends `payload` to `ip:port` and returns the first reply, or nil on timeout/failure.
    ///
    /// One datagram in, one datagram out — the shape of a NetBIOS node-status query, an SNMP get,
    /// or a unicast SSDP M-SEARCH.
    static func exchange(
        _ ip: String,
        port: UInt16,
        payload: Data,
        timeoutMs: Int,
        using parameters: NWParameters = .udp
    ) async -> Data? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }

        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: parameters)
        let queue = DispatchQueue.global(qos: .userInitiated)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let gate = ConnectionGate(connection)
            let timeoutWork = DispatchWorkItem { gate.finish { continuation.resume(returning: nil) } }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { _ in })
                    connection.receiveMessage { data, _, _, _ in
                        timeoutWork.cancel()
                        gate.finish { continuation.resume(returning: data) }
                    }
                case .failed, .cancelled:
                    timeoutWork.cancel()
                    gate.finish { continuation.resume(returning: nil) }
                case .setup, .preparing, .waiting:
                    break
                @unknown default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeoutWork)
            connection.start(queue: queue)
        }
    }
}
