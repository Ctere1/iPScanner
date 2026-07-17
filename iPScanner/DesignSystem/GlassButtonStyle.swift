import SwiftUI

/// A button that reads as glass.
///
/// Scoped narrowly: this is for buttons sitting **on** a glass surface where `.bordered` would draw
/// an opaque control over a translucent panel and break the illusion. It is not a replacement for
/// `.bordered` everywhere — stock AppKit controls are better at being controls (focus rings, key
/// equivalents, accessibility, the pressed states people already recognise), and swapping them out
/// wholesale trades real affordances for a look.
///
/// `.borderedProminent` on the primary action stays `.borderedProminent`.
struct GlassButtonStyle: ButtonStyle {
    var config: GlassConfig = .card
    var horizontalPadding: CGFloat = DesignTokens.Spacing.section
    var verticalPadding: CGFloat = DesignTokens.Spacing.tight + 2

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .glass(config)
            // Pressed state as a brightness shift rather than an opacity one: dropping opacity on a
            // translucent surface fades it toward whatever is behind the window, so a pressed button
            // over a light desktop got *lighter* and over a dark one got darker.
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    /// `.buttonStyle(.glass)` — for buttons on a glass surface. See the type's note on scope.
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}
