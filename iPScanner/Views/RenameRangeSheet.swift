import SwiftUI

// MARK: - Rename saved range sheet

struct RenameRangeSheet: View {
    let range: String
    let initialName: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var fieldFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Range")
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .monospaced()
                    .font(.callout)
                Text("Add a friendly name (e.g. Home, Office VLAN, Lab)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $name, prompt: Text("Optional"))
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocus)
                .onSubmit { save() }

            HStack {
                if !initialName.isEmpty {
                    Button("Clear", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            name = initialName
            fieldFocus = true
        }
    }

    private func save() {
        onSave(name)
        dismiss()
    }
}
