import SwiftUI

/// A padded surface with a background.
///
/// Thin on purpose. It owns the padding-plus-`.glass` pairing and nothing else — no title slot, no
/// header, no optional footer. The app's existing groupings (`HostInspector.actionGroup`, the
/// inspector's sections) already differ enough from each other that a card trying to serve all of
/// them would grow a parameter per caller and stop being reusable in the way that matters.
struct GlassCard<Content: View>: View {
    var config: GlassConfig = .card
    var padding: CGFloat = DesignTokens.Spacing.section
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .glass(config)
    }
}

/// An accent-tinted tile, as used for the inspector's device icon.
///
/// Not glass: this is a fill *on* a surface, not a surface. `Color.accentColor.opacity(0.15)` and a
/// radius-8 rounded rect were written out longhand at two call sites in the inspector and a third,
/// at a different opacity, for the imported-targets chip.
struct AccentTile<Content: View>: View {
    var size: CGFloat?
    var opacity: Double = DesignTokens.Opacity.accentFill
    var cornerRadius: CGFloat = DesignTokens.Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(opacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
