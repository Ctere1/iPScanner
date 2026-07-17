import SwiftUI

/// The column toggles, written once.
///
/// The toolbar and the overflow menu each had their own copy, and they had already drifted — the
/// overflow copy was missing Show All / Reset to Default. Adding a column is now one enum case.
struct ColumnsMenu: View {
    let columns: ColumnVisibility

    var body: some View {
        ForEach(ColumnVisibility.Column.allCases) { column in
            Toggle(column.title, isOn: columns.binding(for: column))
        }
        Divider()
        Button("Show All") { columns.showAll() }
        Button("Reset to Default") { columns.resetToDefaults() }
    }
}
