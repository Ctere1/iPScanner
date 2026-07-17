import SwiftUI

/// The export actions, written once.
///
/// The toolbar and the overflow menu each had their own copy of these eight buttons — the same
/// drift ColumnsMenu was extracted to fix, which was only ever applied to the columns. Adding a
/// format is now one enum case.
struct ExportMenu: View {
    let exporter: ExportCoordinator

    var body: some View {
        ForEach(ExportCoordinator.Format.allCases) { format in
            Button(format.saveTitle) { exporter.save(format) }
        }
        Divider()
        ForEach(ExportCoordinator.Format.allCases) { format in
            Button(format.copyTitle) { exporter.copy(format) }
        }
    }
}
