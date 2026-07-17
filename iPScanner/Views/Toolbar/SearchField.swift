import SwiftUI

/// The table's search box.
///
/// The full-width toolbar and the narrower ones each had their own copy, differing only in the
/// minimum width the tight layout needs.
struct SearchField: View {
    @Bindable var controller: ScanController
    /// Tight layouts give it less floor to stand on; everything else uses 90.
    var minWidth: CGFloat = 90
    @FocusState.Binding var focused: Bool

    var body: some View {
        TextField("", text: $controller.searchQuery, prompt: Text("Search…"))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: minWidth, maxWidth: 200)
            .focused($focused)
    }
}
