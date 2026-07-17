import SwiftUI

/// A `key   value` row, as used by the inspector and the subnet calculator.
///
/// Both had grown their own copy of this layout — including the same minWidth/layoutPriority pair
/// and the bug it fixes, described below.
struct InfoRow: View {
    let key: String
    let value: String?
    var font: Font = .callout
    var monospaced = false
    /// Rendered when `value` is nil or empty. The subnet calculator has no absent values, so it
    /// passes nil and gets nothing rather than an em dash it would never show.
    var placeholder: String? = "—"
    var valueLineLimit: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // A hard `width: 80` let a longer key ("RTT (initial)") overflow its frame and draw
            // over the value. Give the column a floor, not a ceiling, and let it truncate.
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 80, alignment: .leading)
                .layoutPriority(1)
            Group {
                if let value, !value.isEmpty {
                    Text(value)
                        .textSelection(.enabled)
                        .lineLimit(valueLineLimit)
                } else if let placeholder {
                    Text(placeholder).foregroundStyle(.tertiary)
                }
            }
            .font(font)
            .monospaced(monospaced)
            Spacer(minLength: 0)
        }
    }
}
