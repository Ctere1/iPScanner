import XCTest
@testable import iPScanner

/// The host table's index rules. These lived inside ScanController, which had no tests at all —
/// and the IP-reuse guard below is the subtlest thing in the scan path.
final class HostStoreTests: XCTestCase {

    private func host(_ ip: String, status: iPScanner.Host.Status = .alive) -> iPScanner.Host {
        iPScanner.Host(ip: ip, status: status)
    }

    // MARK: - Upsert

    func testUpsertAppendsNewHosts() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        store.upsert(host("10.0.0.2"))
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.hosts.map(\.ip), ["10.0.0.1", "10.0.0.2"])
    }

    func testUpsertMergesAnExistingIPRatherThanDuplicating() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        store.upsert(iPScanner.Host(ip: "10.0.0.1", hostname: "router.local", status: .alive))
        XCTAssertEqual(store.count, 1, "the same IP must not produce a second row")
        XCTAssertEqual(store.hosts[0].hostname, "router.local")
    }

    func testUpsertPreservesTheOriginalRowIdentity() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        let originalID = store.hosts[0].id
        store.upsert(iPScanner.Host(ip: "10.0.0.1", hostname: "x.local", status: .alive))
        XCTAssertEqual(store.hosts[0].id, originalID, "merging must not re-identify the row")
    }

    func testAliveCountIgnoresDeadHosts() {
        var store = HostStore()
        store.upsert(host("10.0.0.1", status: .alive))
        store.upsert(host("10.0.0.2", status: .dead))
        store.upsert(host("10.0.0.3", status: .alive))
        XCTAssertEqual(store.aliveCount, 2)
        XCTAssertEqual(store.count, 3)
    }

    // MARK: - Index

    func testIndexFindsTheHost() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        store.upsert(host("10.0.0.2"))
        let target = store.hosts[1]
        XCTAssertEqual(store.index(of: target.id, ip: target.ip), 1)
    }

    func testIndexIsNilForAnUnknownIP() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        XCTAssertNil(store.index(of: store.hosts[0].id, ip: "10.99.99.99"))
    }

    /// The guard that earns its keep: a refresh started before a restore holds an id that no longer
    /// belongs to that IP. Without the id check it would write its results onto whoever holds the
    /// IP now.
    func testIndexRejectsAStaleIDAtAReusedIP() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        let staleID = store.hosts[0].id

        store.replaceAll(with: [host("10.0.0.1")])   // same IP, different host
        let freshID = store.hosts[0].id
        XCTAssertNotEqual(staleID, freshID)

        XCTAssertNil(store.index(of: staleID, ip: "10.0.0.1"), "a stale id must not resolve")
        XCTAssertEqual(store.index(of: freshID, ip: "10.0.0.1"), 0)
    }

    func testUpdateRejectsAStaleID() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        let staleID = store.hosts[0].id
        store.replaceAll(with: [host("10.0.0.1")])

        let applied = store.update(id: staleID, ip: "10.0.0.1") { $0.hostname = "wrong.local" }
        XCTAssertFalse(applied)
        XCTAssertNil(store.hosts[0].hostname, "the current host must be untouched")
    }

    func testUpdateAppliesToTheRightHost() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        store.upsert(host("10.0.0.2"))
        let target = store.hosts[1]
        XCTAssertTrue(store.update(id: target.id, ip: target.ip) { $0.hostname = "two.local" })
        XCTAssertNil(store.hosts[0].hostname)
        XCTAssertEqual(store.hosts[1].hostname, "two.local")
    }

    // MARK: - Removal

    /// Removing shifts every later element, so a partially-updated index would silently point rows
    /// at their neighbours.
    func testRemoveRebuildsTheIndex() {
        var store = HostStore()
        for i in 1...5 { store.upsert(host("10.0.0.\(i)")) }
        let survivor = store.hosts[4]
        store.remove(ids: Set(store.hosts.prefix(3).map(\.id)))

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.index(of: survivor.id, ip: survivor.ip), 1,
                       "the index must follow the host to its new position")
    }

    func testRemoveOfNothingIsANoOp() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        store.remove(ids: [])
        XCTAssertEqual(store.count, 1)
    }

    func testRemoveAllClearsTheIndexToo() {
        var store = HostStore()
        store.upsert(host("10.0.0.1"))
        let id = store.hosts[0].id
        store.removeAll()
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.index(of: id, ip: "10.0.0.1"))
    }

    // MARK: - Replace

    /// A snapshot is a user-supplied file and may repeat an IP. Last one wins; it must not trap.
    func testReplaceAllToleratesDuplicateIPs() {
        var store = HostStore()
        let dupes = [
            iPScanner.Host(ip: "10.0.0.1", hostname: "first", status: .alive),
            iPScanner.Host(ip: "10.0.0.1", hostname: "second", status: .alive)
        ]
        store.replaceAll(with: dupes)
        XCTAssertEqual(store.count, 2, "both rows are kept")
        let resolved = store.index(of: dupes[1].id, ip: "10.0.0.1")
        XCTAssertEqual(resolved, 1, "the index resolves to the last of the duplicates")
    }

    func testUpsertAfterReplaceAllMergesRatherThanAppends() {
        var store = HostStore()
        store.replaceAll(with: [host("10.0.0.1")])
        store.upsert(iPScanner.Host(ip: "10.0.0.1", hostname: "restored.local", status: .alive))
        XCTAssertEqual(store.count, 1, "replaceAll must leave a usable index behind")
        XCTAssertEqual(store.hosts[0].hostname, "restored.local")
    }
}
