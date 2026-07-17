import SwiftUI
import AppKit

/// `NSVisualEffectView`, and nothing else.
///
/// No corner radius, no stroke, no shadow, no fallback logic — those are `GlassBackground`'s, and
/// keeping them out of here is what lets this file stay the size it is. This is a bridge, not a
/// component: the only reason it exists is that SwiftUI has no native access to AppKit's material
/// vocabulary.
///
/// `state` is pinned to `.active` on purpose. The default, `.followsWindowActiveState`, drains the
/// material to grey whenever the window loses focus — correct for a document window's chrome,
/// wrong here, where the user tabs to Terminal to check something and comes back to an app that
/// looks disabled.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = isEmphasized
    }
}
