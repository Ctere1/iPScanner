import SwiftUI

extension View {
    /// Puts this content on a glass surface.
    ///
    /// The one entry point. Everything else in `DesignSystem/` is reachable from here, and nothing
    /// outside it should construct a `GlassBackground` or a `VisualEffectView` directly — going
    /// through the modifier is what guarantees the Reduce Transparency fallback and the content
    /// scrim come along with the material instead of being remembered separately.
    func glass(_ config: GlassConfig) -> some View {
        modifier(GlassSurface(config: config))
    }
}

private struct GlassSurface: ViewModifier {
    let config: GlassConfig

    func body(content: Content) -> some View {
        content
            // Order matters: scrim first, so it lands *between* the material and the content rather
            // than over the text. `.background` stacks outward from the content, so the later
            // modifier is the further-back layer.
            .background { scrim }
            .background { GlassBackground(config: config) }
    }

    @ViewBuilder
    private var scrim: some View {
        if case .highContrast = config.contentTint {
            RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                .fill(config.opaqueFallback.opacity(DesignTokens.Opacity.scrim))
        }
    }
}
