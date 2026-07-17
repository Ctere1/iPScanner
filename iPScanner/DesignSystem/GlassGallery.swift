import SwiftUI

/// Every preset on one canvas, for reviewing the design language without hunting it across the app.
///
/// This exists because the presets are only honest in context: a material is defined by what shows
/// through it, so a `GlassConfig` inspected as a value tells you nothing about whether it is
/// readable. Open the preview, toggle light/dark and Reduce Transparency, and the answer is visible.
///
/// Not shipped UI — nothing constructs it outside the preview below.
struct GlassGallery: View {
    private struct Sample: Identifiable {
        let id: String
        let config: GlassConfig
    }

    private let samples: [Sample] = [
        .init(id: "sidebar", config: .sidebar),
        .init(id: "toolbar", config: .toolbar),
        .init(id: "statusBar", config: .statusBar),
        .init(id: "panel", config: .panel),
        .init(id: "popover", config: .popover),
        .init(id: "card", config: .card),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.surface) {
                ForEach(samples) { sample in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                        Text(sample.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Monospaced sample text on purpose: this is the content that actually
                        // stresses a material, and the reason `.panel` is `.highContrast`.
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                            Text("192.168.1.104").monospaced()
                            Text("A4:83:E7:2C:19:0B")
                                .monospaced()
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignTokens.Spacing.section)
                        .glass(sample.config)
                    }
                }

                Divider()

                HStack(spacing: DesignTokens.Spacing.inline) {
                    Button("Glass") {}
                        .buttonStyle(.glass)
                    Button("Disabled") {}
                        .buttonStyle(.glass)
                        .disabled(true)
                    Button("Bordered") {}
                    Button("Prominent") {}
                        .buttonStyle(.borderedProminent)
                }

                GlassCard {
                    Text("GlassCard").frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: DesignTokens.Spacing.inline) {
                    AccentTile(size: 48) {
                        Image(systemName: "wifi.router")
                            .font(.system(size: 22))
                            .foregroundStyle(.tint)
                    }
                    AccentTile(
                        opacity: DesignTokens.Opacity.accentFillSubtle,
                        cornerRadius: DesignTokens.Radius.small
                    ) {
                        Text("12 targets")
                            .font(.caption)
                            .padding(.horizontal, DesignTokens.Spacing.inline)
                            .padding(.vertical, DesignTokens.Spacing.tight)
                    }
                }
            }
            .padding(DesignTokens.Spacing.surface)
        }
        // A busy backdrop. Against a flat fill every material looks fine, which is exactly how an
        // unreadable one ships.
        .background {
            LinearGradient(
                colors: [.blue, .purple, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(width: 380, height: 720)
    }
}

#Preview("Glass — Light") {
    GlassGallery().preferredColorScheme(.light)
}

#Preview("Glass — Dark") {
    GlassGallery().preferredColorScheme(.dark)
}
