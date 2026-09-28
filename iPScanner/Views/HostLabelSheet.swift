import SwiftUI

struct HostLabelSheet: View {
    let host: Host
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @FocusState private var focused: Bool

    init(host: Host, initialValue: String, onSave: @escaping (String) -> Void) {
        self.host = host
        self.onSave = onSave
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Device label").font(.headline)
            Text(host.ip).monospaced().foregroundStyle(.secondary)
            TextField("Label", text: $value, prompt: Text("Office printer #work"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            Text("Use a name or #tags. Leave empty to remove the label.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(value); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { focused = true }
    }
}
