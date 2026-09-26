import Foundation
import Network

enum WakeOnLAN {
    enum WoLError: Error { case invalidMAC, timedOut, cancelled, sendFailed(Error) }

    static func wake(
        mac: String,
        broadcast: String = "255.255.255.255",
        port: UInt16 = 9
    ) async throws {
        guard let payload = magicPacket(mac: mac) else { throw WoLError.invalidMAC }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw WoLError.invalidMAC }

        let params: NWParameters = .udp
        if let opts = params.defaultProtocolStack.transportProtocol as? NWProtocolUDP.Options {
            _ = opts
        }
        // Allow broadcast on the underlying socket.
        params.allowLocalEndpointReuse = true
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(broadcast),
            port: nwPort,
            using: params
        )
        let queue = DispatchQueue.global(qos: .userInitiated)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let state = SendState()

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            state.finish(.failure(WoLError.sendFailed(error)),
                                         continuation: continuation,
                                         connection: connection)
                        } else {
                            state.finish(.success(()),
                                         continuation: continuation,
                                         connection: connection)
                        }
                    })
                case .failed(let error):
                    state.finish(.failure(WoLError.sendFailed(error)),
                                 continuation: continuation,
                                 connection: connection)
                case .cancelled:
                    state.finish(.failure(WoLError.cancelled),
                                 continuation: continuation,
                                 connection: connection)
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + 1.5) {
                state.finish(.failure(WoLError.timedOut),
                             continuation: continuation,
                             connection: connection)
            }

            connection.start(queue: queue)
        }
    }

    static func wakeAll(macs: [String]) async -> (sent: Int, failed: Int) {
        await withTaskGroup(of: Bool.self) { group in
            for mac in Set(macs) {
                group.addTask {
                    do { try await Self.wake(mac: mac); return true } catch { return false }
                }
            }
            var sent = 0, failed = 0
            for await success in group { if success { sent += 1 } else { failed += 1 } }
            return (sent, failed)
        }
    }

    static func magicPacket(mac: String) -> Data? {
        guard let address = MACAddress(mac), address.kind == .universal || address.kind == .local else { return nil }
        var payload = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { payload.append(contentsOf: address.bytes) }
        return payload
    }

    private final class SendState: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func finish(
            _ result: Result<Void, Error>,
            continuation: CheckedContinuation<Void, Error>,
            connection: NWConnection
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            connection.cancel()
            continuation.resume(with: result)
        }
    }
}
