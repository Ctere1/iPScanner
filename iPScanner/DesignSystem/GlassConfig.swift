import SwiftUI
import AppKit

/// What a glass surface is: a material, and the decisions that make text on top of it readable.
///
/// This type is a value and nothing else — no `View`, no `@Environment`, no drawing. That split is
/// the point. `GlassBackground` renders a config; `View+Glass` applies one; presets name useful
/// ones. A surface can be described, compared and tested without a view hierarchy existing.
///
/// `material` is an `NSVisualEffectView.Material` rather than a SwiftUI `Material` because the
/// AppKit vocabulary is *semantic*: `.sidebar`, `.headerView`, `.popover` are roles the system
/// already tunes per-appearance and per-context. SwiftUI's four thicknesses are not roles, they are
/// thicknesses — picking `.ultraThin` for a sidebar is a guess about opacity, while picking
/// `.sidebar` is a statement of intent that macOS renders correctly in light, dark, increased
/// contrast, and whatever Apple decides vibrancy means next release.
struct GlassConfig: Equatable {

    /// How content on this surface stays legible.
    ///
    /// Legibility is a property of the *surface*, not of each label drawn on it — which is why this
    /// lives here and not at the call sites.
    ///
    /// There is deliberately no `.vibrant` case. AppKit vibrancy works by blending an effect view's
    /// **subviews**, and SwiftUI content sitting on `.background(VisualEffectView(…))` is not a
    /// subview of it — it is drawn over it. A `.vibrant` case would have been an API that reads as a
    /// promise and compiles to nothing. Material emphasis, which *is* reachable from here, is a
    /// separate axis and lives on `isEmphasized`.
    enum ContentTint: Equatable {
        /// Standard label colours. Correct for anything with normal type and generous spacing.
        case standard
        /// Lays a scrim between the blur and the content.
        ///
        /// For dense monospaced text. A MAC address over live blur is where a material stops being
        /// decoration and becomes a legibility bug: the glyphs are thin and high-frequency, and the
        /// backdrop moves when the window moves.
        case highContrast
    }

    struct Stroke: Equatable {
        var color: Color
        var width: CGFloat
    }

    struct Elevation: Equatable {
        var color: Color
        var radius: CGFloat
        var y: CGFloat
    }

    var material: NSVisualEffectView.Material

    /// `.withinWindow` blends against the window's own content; `.behindWindow` samples the desktop.
    ///
    /// The default is deliberate. `.behindWindow` is true glassmorphism, but it needs a non-opaque
    /// window — which costs the window server's opaque-surface fast path on a view that redraws a
    /// 254-row table on every scan tick — and `NavigationSplitView`'s sidebar already renders
    /// behind-window material on its own, so a second layer over the same region double-blurs.
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    var isEmphasized: Bool = false

    var cornerRadius: CGFloat = DesignTokens.Radius.card

    var stroke: Stroke?

    var elevation: Elevation?

    var contentTint: ContentTint = .standard

    /// The solid fill this collapses to under Reduce Transparency.
    ///
    /// Required rather than optional, and it has no default. A config that cannot say what it looks
    /// like without blur is a config that will ship an unreadable panel to everyone who turns
    /// transparency off — and that is an accessibility setting, so "nobody does that" is wrong.
    /// Making it non-optional means the fallback is answered when the surface is designed, by the
    /// person designing it, instead of being discovered later by a user who cannot read the app.
    var opaqueFallback: Color
}

// MARK: - Variation

/// Open/Closed, part one: vary a preset without a new type, a new init, or an edit to this file.
///
/// `GlassConfig.card.cornerRadius(.large)` is a new surface. It did not require `GlassConfig` to
/// learn about it.
extension GlassConfig {
    func cornerRadius(_ radius: CGFloat) -> Self {
        var copy = self
        copy.cornerRadius = radius
        return copy
    }

    func stroked(_ stroke: Stroke?) -> Self {
        var copy = self
        copy.stroke = stroke
        return copy
    }

    func elevated(_ elevation: Elevation?) -> Self {
        var copy = self
        copy.elevation = elevation
        return copy
    }

    func tinted(_ tint: ContentTint) -> Self {
        var copy = self
        copy.contentTint = tint
        return copy
    }

    func emphasized(_ emphasized: Bool = true) -> Self {
        var copy = self
        copy.isEmphasized = emphasized
        return copy
    }
}
