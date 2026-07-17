import XCTest
@testable import iPScanner

/// The half of the label-corruption fix that is not view code.
///
/// The bug: the inspector committed an edit through a closure that re-read the *current* selection,
/// so typing a label on host A and clicking host B wrote A's text onto B. Keying by an anchor
/// captured when editing began is what makes the commit name the right host — including when that
/// host is no longer selected, or no longer in the table at all.
@MainActor
final class LabelAnchorTests: XCTestCase {

    /// A store of its own per test, following ColumnVisibilityTests. This used to construct a bare
    /// `ScanController()` — which read the developer's real saved labels — and then clear the
    /// dictionary to paper over it.
    private func makeController(_ name: String = #function) -> ScanController {
        let suite = "LabelAnchorTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        return ScanController(
            labelStore: LabelStore(store: PersistedStore(defaults: defaults)),
            savedRangeStore: SavedRangeStore(store: PersistedStore(defaults: defaults))
        )
    }

    func testSetsLabelByAnchor() {
        let c = makeController()
        c.setLabel("NAS", forAnchor: "AA:BB:CC:00:00:01")
        XCTAssertEqual(c.labels["AA:BB:CC:00:00:01"], "NAS")
    }

    /// The whole point: committing against A's anchor must not touch B, whoever is selected now.
    func testWritingOneAnchorLeavesOthersAlone() {
        let c = makeController()
        c.setLabel("Host B label", forAnchor: "anchor-B")
        c.setLabel("Host A label", forAnchor: "anchor-A")
        XCTAssertEqual(c.labels["anchor-A"], "Host A label")
        XCTAssertEqual(c.labels["anchor-B"], "Host B label", "B must be untouched by an edit aimed at A")
    }

    func testEmptyOrBlankClearsTheLabel() {
        let c = makeController()
        c.setLabel("temp", forAnchor: "anchor-A")
        c.setLabel("   ", forAnchor: "anchor-A")
        XCTAssertNil(c.labels["anchor-A"], "a blank label is no label")

        c.setLabel("temp", forAnchor: "anchor-A")
        c.setLabel(nil, forAnchor: "anchor-A")
        XCTAssertNil(c.labels["anchor-A"])
    }

    func testLabelIsTrimmed() {
        let c = makeController()
        c.setLabel("  Office NAS \n", forAnchor: "anchor-A")
        XCTAssertEqual(c.labels["anchor-A"], "Office NAS")
    }

    /// The host-based overload must agree with the anchor-based one — anchor is `mac ?? ip`.
    func testHostOverloadUsesTheHostsAnchor() {
        let c = makeController()
        let withMAC = iPScanner.Host(ip: "10.0.0.1", mac: "AA:BB:CC:00:00:01", status: .alive)
        c.setLabel("Router", for: withMAC)
        XCTAssertEqual(c.labels["AA:BB:CC:00:00:01"], "Router")

        let noMAC = iPScanner.Host(ip: "10.0.0.9", status: .alive)
        c.setLabel("Printer", for: noMAC)
        XCTAssertEqual(c.labels["10.0.0.9"], "Printer", "with no MAC the anchor falls back to the IP")
    }

    /// A commit can land after the host is gone (panel closed, row deleted, filtered out). It must
    /// still be recorded, not dropped — dropping it is how the old code lost your typing.
    func testCommitSucceedsForAnAnchorNoLongerInTheTable() {
        let c = makeController()
        c.setLabel("typed before it vanished", forAnchor: "anchor-of-deleted-host")
        XCTAssertEqual(c.labels["anchor-of-deleted-host"], "typed before it vanished")
    }
}
