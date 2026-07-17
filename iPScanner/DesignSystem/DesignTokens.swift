import SwiftUI

/// The numbers the UI is allowed to use.
///
/// Every one of these was a literal repeated at three or four call sites, and they had already
/// drifted the way repeated literals do: the icon tile rounded at 8, the ping sparkline at 6, the
/// imported-targets chip at 6, and nothing recorded which was intentional. Same story for the
/// accent fills — `0.15` in the inspector, `0.10` in the chip, no reason for the gap.
///
/// Named, they are a decision. Inline, they are a guess someone made once.
enum DesignTokens {

    /// Corner radii. Continuous curvature is applied at the shape, not here — see `GlassBackground`.
    enum Radius {
        /// Inline chips and small wells that sit *inside* a section.
        static let small: CGFloat = 6
        /// Cards, tiles, and anything that reads as its own surface.
        static let card: CGFloat = 8
        /// Floating surfaces — popovers and detached panels.
        static let large: CGFloat = 12
    }

    /// Spacing. The ladder is deliberately short: four rungs, no in-between values.
    ///
    /// The app previously used 2, 4, 6, 8, 10, 12, 14, 16 and 20 — nine values for what is really
    /// four intentions, which is how a 14 and a 16 end up side by side meaning the same thing.
    enum Spacing {
        /// Between a label and the thing it labels.
        static let tight: CGFloat = 4
        /// Between controls in a row.
        static let inline: CGFloat = 8
        /// Between sections within a surface.
        static let section: CGFloat = 12
        /// Between a surface's edge and its contents.
        static let surface: CGFloat = 16
    }

    /// Opacities for fills drawn over a material.
    ///
    /// These are tuned against blur, not against a solid background. A fill that reads as a gentle
    /// tint over `windowBackgroundColor` reads as mud over `.sidebar` material, because the material
    /// is already doing tonal work underneath it.
    enum Opacity {
        /// Accent-tinted fills: the inspector's device tile, selected chips.
        static let accentFill: Double = 0.15
        /// The same idea, one step back — for fills that sit behind text rather than an icon.
        static let accentFillSubtle: Double = 0.10
        /// Hairline borders. Any heavier and the stroke, not the blur, defines the surface.
        static let hairline: Double = 0.08
        /// The scrim `GlassConfig.ContentTint.highContrast` lays between blur and text.
        ///
        /// 0.6 is the point where a monospaced MAC address stops shimmering against a moving
        /// backdrop while the surface still reads as translucent. Below ~0.45 the glyphs crawl;
        /// above ~0.75 there is no reason to be using a material at all.
        static let scrim: Double = 0.6
    }
}
