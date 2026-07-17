import SwiftUI

/// The scope filter toggles, written once.
///
/// The toolbar and the overflow menu each had their own copy, and they had drifted: the overflow
/// one folded the dead-host toggle in with the scope filters and dropped the divider before
/// "Clear filters".
///
/// That folding is deliberate, not drift — when the window is wide the dead-host toggle is a
/// checkbox of its own, and there is no room for it when it is narrow. Hence the parameter rather
/// than one shape forced on both.
struct FilterMenu: View {
    @Bindable var controller: ScanController

    /// Whether to fold the dead-host toggle in with the scope filters, for the compact layout that
    /// has nowhere else to put it.
    var includeDeadHosts = false

    var body: some View {
        Toggle("Has open ports", isOn: $controller.filterHasOpenPorts)
        Toggle("Has label", isOn: $controller.filterHasLabel)
        Toggle("Has vendor", isOn: $controller.filterHasVendor)
        Toggle("Identified device type", isOn: $controller.filterIdentifiedDevice)
        if includeDeadHosts {
            Toggle("Dead hosts", isOn: $controller.showDeadHosts)
        }
        if controller.hasActiveScopeFilters {
            Divider()
            Button("Clear filters") { controller.clearScopeFilters() }
        }
    }
}
