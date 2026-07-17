import Foundation
@testable import iPScanner

/// A `HostDiscovering` that replays a scripted event stream instead of touching the network.
///
/// The controller used to build a `NetworkScanner` inside `start()`, so exercising the scan
/// lifecycle meant actually scanning a subnet. This is what the old `NetworkScanning` protocol
/// should have allowed and could not: it declared a method nobody called.
struct FakeScanner: HostDiscovering {
    let events: [ScanEvent]

    /// Delay between events, to keep a test's assertions interleavable with the stream.
    var stepNanoseconds: UInt64 = 0

    init(_ events: [ScanEvent]) {
        self.events = events
    }

    /// A plain "everything answered" run: one host event per address, then `.done`.
    static func allAlive(_ addresses: [String]) -> FakeScanner {
        var events: [ScanEvent] = []
        for (i, ip) in addresses.enumerated() {
            events.append(.progress(scanned: i + 1, total: addresses.count))
            events.append(.host(iPScanner.Host(ip: ip, rttMs: 1.0, ttl: 64, status: .alive)))
        }
        events.append(.done)
        return FakeScanner(events)
    }

    func scan(addresses: [String]) -> AsyncStream<ScanEvent> {
        let events = self.events
        let step = stepNanoseconds
        return AsyncStream { continuation in
            Task {
                for event in events {
                    if Task.isCancelled { break }
                    if step > 0 { try? await Task.sleep(nanoseconds: step) }
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
