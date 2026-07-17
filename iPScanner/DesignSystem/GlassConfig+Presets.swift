import SwiftUI
import AppKit

/// The surfaces this app actually has.
///
/// Open/Closed, part two: these are static members in an extension, so adding a surface is adding a
/// `static let` — `GlassConfig` itself never reopens, and nothing that consumes a config has to
/// learn the new case exists.
///
/// They are deliberately **not** an enum. An enum would put every surface in one closed list, force
/// each addition to edit the type, and hand every `switch` over it a new case to handle. The whole
/// difference between `.card` here and `case card` there is whether the next surface is an addition
/// or a modification.
extension GlassConfig {

    /// The saved-ranges list. `.sidebar` is the one material macOS gives real behind-window
    /// treatment to for free inside a `NavigationSplitView`.
    static let sidebar = GlassConfig(
        material: .sidebar,
        cornerRadius: 0,
        opaqueFallback: Color(nsColor: .windowBackgroundColor)
    )

    /// The toolbar strip. `.headerView` is what AppKit puts behind a real window toolbar, so this
    /// matches the titlebar above it rather than approximating it.
    static let toolbar = GlassConfig(
        material: .headerView,
        cornerRadius: 0,
        opaqueFallback: Color(nsColor: .windowBackgroundColor)
    )

    /// The status strip. Same material as the toolbar: they are the same kind of thing at opposite
    /// ends of the window, and the old `.bar` was `.headerView` by another name.
    static let statusBar = GlassConfig(
        material: .headerView,
        cornerRadius: 0,
        opaqueFallback: Color(nsColor: .windowBackgroundColor)
    )

    /// The host detail sheet.
    ///
    /// The one place `.behindWindow` is right, and for a reason the others are not: a sheet is its
    /// own window, so "behind" means the app window it is covering — the table it was opened from,
    /// blurred underneath it. That is the actual glassmorphism idea, and here it costs nothing,
    /// because the surface being made non-opaque is a 380pt panel rather than the window that
    /// repaints a 254-row table on every scan tick.
    ///
    /// `.hudWindow` over `.popover`: this is a floating panel, not a tooltip, and the HUD material
    /// is the one AppKit tunes for a surface with its own content rather than a callout of someone
    /// else's.
    ///
    /// `.highContrast` is not a preference. This panel is a column of monospaced IPs, MACs and
    /// anchors — precisely the content that falls apart over live blur — and the blur under it is
    /// now a live table rather than flat chrome, which is the worst backdrop of the lot.
    static let sheetPanel = GlassConfig(
        material: .hudWindow,
        blending: .behindWindow,
        cornerRadius: 0,
        contentTint: .highContrast,
        opaqueFallback: Color(nsColor: .windowBackgroundColor)
    )

    /// Popovers: the subnet calculator, the warnings list, the diff summary.
    ///
    /// The only preset with elevation, because it is the only one that genuinely floats — the rest
    /// are edge-to-edge chrome, and a shadow on a surface with no gap to cast into is just a dark line.
    static let popover = GlassConfig(
        material: .popover,
        cornerRadius: DesignTokens.Radius.large,
        elevation: .init(color: .black.opacity(0.18), radius: 12, y: 4),
        opaqueFallback: Color(nsColor: .windowBackgroundColor)
    )

    /// Cards and tiles inside a surface — the inspector's device tile, the imported-targets chip.
    static let card = GlassConfig(
        material: .underWindowBackground,
        cornerRadius: DesignTokens.Radius.card,
        stroke: .init(color: .primary.opacity(DesignTokens.Opacity.hairline), width: 1),
        opaqueFallback: Color(nsColor: .controlBackgroundColor)
    )
}
