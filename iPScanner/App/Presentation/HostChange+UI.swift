import SwiftUI

// The SwiftUI half of HostChange. It lives here rather than on the model because Models/ compiles
// into the ipscanner CLI target, which has no SwiftUI — the model carries the symbol name (a plain
// string the CLI can print), and the Color stays on this side of the layer line.
//
// There were two prior attempts at this: a `tint` on the model returning a colour *name* as a
// String, which nothing ever called, and a private `diffTint` in ContentView returning the real
// Color, which everything called. This is the one that survives.
extension HostChange.Kind {
    var tint: Color {
        switch self {
        case .new: .green
        case .modified: .yellow
        case .missing: .red
        }
    }
}

extension HostChange {
    var tint: Color { kind.tint }
}
