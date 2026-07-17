import XCTest
@testable import iPScanner

@MainActor
final class ColumnVisibilityTests: XCTestCase {

    /// A store of its own per test — `.standard` would leak state between runs and pick up the
    /// real app's saved layout.
    private func makeStore(_ name: String = #function) -> UserDefaults {
        let suite = "ColumnVisibilityTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func testMACIsVisibleByDefault() {
        let columns = ColumnVisibility(store: makeStore())
        XCTAssertTrue(columns.isVisible(.mac), "MAC must be shown out of the box")
    }

    func testDefaultsMatchTheDeclaredSet() {
        let columns = ColumnVisibility(store: makeStore())
        XCTAssertEqual(columns.visible, ColumnVisibility.Column.defaults)
        XCTAssertEqual(columns.visible, [.label, .hostname, .mac, .vendor, .ports])
        for hidden in [ColumnVisibility.Column.title, .rtt, .ttl] {
            XCTAssertFalse(columns.isVisible(hidden), "\(hidden) should be off by default")
        }
    }

    /// The migration rests on this: writing on init would freeze whatever the default was at the
    /// time of first launch, so a later default change could never reach an existing install.
    func testInitWritesNothing() {
        let store = makeStore()
        _ = ColumnVisibility(store: store)
        for column in ColumnVisibility.Column.allCases {
            XCTAssertNil(store.object(forKey: column.storageKey), "\(column) must not be written on init")
        }
    }

    /// The other half of the migration: an explicit choice outranks a changed default.
    func testExplicitlyHiddenColumnSurvivesADefaultThatSaysOtherwise() {
        let store = makeStore()
        store.set(false, forKey: ColumnVisibility.Column.mac.storageKey)
        let columns = ColumnVisibility(store: store)
        XCTAssertFalse(columns.isVisible(.mac), "a deliberate choice must not be overridden by the default")
    }

    func testExplicitlyShownColumnSurvives() {
        let store = makeStore()
        store.set(true, forKey: ColumnVisibility.Column.ttl.storageKey)
        let columns = ColumnVisibility(store: store)
        XCTAssertTrue(columns.isVisible(.ttl))
    }

    func testSetPersists() {
        let store = makeStore()
        let columns = ColumnVisibility(store: store)
        columns.set(.title, to: true)
        XCTAssertTrue(ColumnVisibility(store: store).isVisible(.title), "choice must survive a relaunch")
        columns.set(.title, to: false)
        XCTAssertFalse(ColumnVisibility(store: store).isVisible(.title))
    }

    func testShowAll() {
        let columns = ColumnVisibility(store: makeStore())
        columns.showAll()
        XCTAssertEqual(columns.visible, Set(ColumnVisibility.Column.allCases))
    }

    func testResetToDefaults() {
        let columns = ColumnVisibility(store: makeStore())
        columns.showAll()
        columns.resetToDefaults()
        XCTAssertEqual(columns.visible, ColumnVisibility.Column.defaults)
    }

    func testBindingReflectsAndMutates() {
        let columns = ColumnVisibility(store: makeStore())
        let binding = columns.binding(for: .rtt)
        XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = true
        XCTAssertTrue(columns.isVisible(.rtt))
    }

    /// Storage keys are a compatibility surface — renaming one silently resets users' layouts.
    func testStorageKeysAreUnchanged() {
        XCTAssertEqual(ColumnVisibility.Column.mac.storageKey, "iPScanner.col.mac")
        XCTAssertEqual(ColumnVisibility.Column.hostname.storageKey, "iPScanner.col.hostname")
        XCTAssertEqual(ColumnVisibility.Column.ports.storageKey, "iPScanner.col.ports")
    }
}
