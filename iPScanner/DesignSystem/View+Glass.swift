import SwiftUI

extension View {
    /// Puts this content on a glass surface.
    ///
    /// The one entry point for in-window chrome. Nothing outside `DesignSystem/` should reach for
    /// `GlassBackground` or `VisualEffectView` directly — going through here is what guarantees the
    /// Reduce Transparency fallback and the readability scrim arrive with the material instead of
    /// being remembered separately.
    ///
    /// The exception is a presentation that owns its own background: a sheet cannot be given one
    /// with `.background`, because the sheet's own surface is drawn over it. Those use
    /// `.presentationBackground { GlassBackground(config:) }`, which is why `GlassBackground` is the
    /// complete surface rather than just the material.
    func glass(_ config: GlassConfig) -> some View {
        background { GlassBackground(config: config) }
    }
}
