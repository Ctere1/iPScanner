import XCTest
@testable import iPScanner

final class DNSResolverTests: XCTestCase {

    /// `reverseLookup`'s timeout must bound wall-clock time even though the
    /// underlying `getnameinfo()` call is blocking and not cooperatively
    /// cancellable — the system resolver can take several seconds (or longer)
    /// to give up on a non-routable address, far past the requested timeout.
    func testReverseLookupHonorsTimeout() async {
        // TEST-NET-1 (RFC 5737): guaranteed non-routable, and NI_NAMEREQD means
        // getnameinfo() has to exhaust the system resolver's own (much longer)
        // timeout before giving up on its own.
        let start = Date()
        let result = await DNSResolver.reverseLookup("192.0.2.1", timeout: .milliseconds(300))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 1.5, "reverseLookup should return near the requested timeout, not wait on the blocking lookup")
    }
}
