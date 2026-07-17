import SwiftUI

/// Renders a `GlassConfig`: material (or its fallback), then stroke, then shadow.
///
/// This view is the **only** place in the app that reads `accessibilityReduceTransparency`.
///
/// That is a structural claim, not a coding-standard one. Every glass surface goes through
/// `.glass(_:)`, `.glass(_:)` goes through here, so a call site cannot forget the check — there is
/// nothing for it to forget. The alternative, asking each surface to remember, is a rule that holds
/// until the first surface added by someone who has not read this comment. Reduce Transparency is
/// an accessibility setting: a surface that ignores it is unreadable, not merely off-brand.
struct GlassBackground: View {
    let config: GlassConfig

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
    }

    var body: some View {
        surface
            .overlay {
                if let stroke = config.stroke {
                    shape.strokeBorder(stroke.color, lineWidth: stroke.width)
                }
            }
            .shadow(
                color: config.elevation?.color ?? .clear,
                radius: config.elevation?.radius ?? 0,
                y: config.elevation?.y ?? 0
            )
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            shape.fill(config.opaqueFallback)
        } else {
            VisualEffectView(
                material: config.material,
                blending: config.blending,
                isEmphasized: config.isEmphasized
            )
            .clipShape(shape)
        }
    }
}
