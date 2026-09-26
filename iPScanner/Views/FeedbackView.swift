import SwiftUI

struct FeedbackView: View {
    @State private var draft = FeedbackDraft()
    @State private var copied = false
    @State private var isSending = false
    @State private var receipt: FeedbackService.Receipt?
    @State private var sendError: String?
    @State private var showPreview = false
    private let environment = FeedbackDraft.environment

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let receipt {
                success(receipt)
            } else {
                editor
                if let sendError {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(sendError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange).textSelection(.enabled)
                        Link("Check existing issues", destination: URL(string: "https://github.com/canberkys/iPScanner/issues")!)
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24).padding(.bottom, 12)
                }
                footer
            }
        }
        .frame(width: 640, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showPreview) { preview }
        .onChange(of: draft.title) { copied = false }
        .onChange(of: draft.details) { copied = false }
        .onChange(of: draft.steps) { copied = false }
        .onChange(of: draft.expected) { copied = false }
        .onChange(of: draft.includeEnvironment) { copied = false }
        .onChange(of: draft.kind) { copied = false }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 24)).foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Feedback").font(.title2.bold())
                Text("Help make iPScanner better.").foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(24)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Feedback type", selection: $draft.kind) {
                    ForEach(FeedbackDraft.Kind.allCases, id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind == .bug ? "ladybug" : "lightbulb").tag(kind)
                    }
                }.pickerStyle(.segmented).labelsHidden()

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Title", hint: "Required")
                    TextField(draft.kind == .bug ? "What went wrong?" : "What would you like to improve?", text: $draft.title)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Report title")
                    fieldLabel("Description", hint: "Required")
                    ZStack(alignment: .topLeading) {
                        if draft.details.isEmpty {
                            Text(draft.kind == .bug ? "Tell us what happened and how it affected your scan." : "Describe your idea and when it would be useful.")
                                .foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.top, 9)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.details)
                            .scrollContentBackground(.hidden).padding(4)
                            .accessibilityLabel("Description")
                    }
                    .frame(height: 80)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.12)))
                    if draft.kind == .bug {
                        fieldLabel("Steps to reproduce", hint: "Optional")
                        TextField("1. Open…  2. Select…  3. Scan…", text: $draft.steps, axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(.roundedBorder).accessibilityLabel("Steps to reproduce")
                        fieldLabel("Expected result", hint: "Optional")
                        TextField("What did you expect to happen?", text: $draft.expected, axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(.roundedBorder).accessibilityLabel("Expected result")
                    }
                }
                .padding(18)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                Toggle(isOn: $draft.includeEnvironment) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Include system information").fontWeight(.medium)
                        Text("App version, macOS version and processor only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch)
            }.padding(20)
        }.disabled(isSending)
    }

    private func fieldLabel(_ title: String, hint: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Label {
                Text("Your report becomes a public GitHub issue. Remove private information before sending. Scan results are not attached.")
            } icon: { Image(systemName: "eye") }
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Preview Report") { showPreview = true }.disabled(isSending)
                Spacer()
                if isSending { ProgressView().controlSize(.small) }
                Button(isSending ? "Sending…" : "Send Feedback", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid || isSending)
            }.controlSize(.large)
        }.padding(.horizontal, 24).padding(.bottom, 20)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Report preview").font(.title3.bold())
                Spacer()
                Button("Done") { showPreview = false }.keyboardShortcut(.cancelAction)
            }
            Text("This is the information that will be shared publicly.")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(draft.title.isEmpty ? "Untitled report" : draft.title).font(.headline)
                    Text(draft.body(environment: environment))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            Button(copied ? "Copied" : "Copy Report") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(draft.title + "\n\n" + draft.body(environment: environment), forType: .string)
                copied = true
            }.disabled(!draft.isValid)
        }.padding(24).frame(width: 540, height: 460)
    }

    private func success(_ receipt: FeedbackService.Receipt) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("Thanks for your feedback").font(.title2.bold())
            Text("Your report has been received as issue #\(receipt.issueNumber).")
                .foregroundStyle(.secondary)
            Link("View on GitHub", destination: receipt.issueURL)
            Button("Write Another Report") {
                draft = FeedbackDraft(); self.receipt = nil; copied = false; sendError = nil
            }.padding(.top, 8)
            Spacer()
        }.frame(maxWidth: .infinity).padding(24)
    }

    private func send() {
        isSending = true
        sendError = nil
        Task {
            do { receipt = try await FeedbackService.send(draft, environment: environment) }
            catch { sendError = error is URLError ? "Delivery could not be confirmed. Check the issue list before retrying to avoid a duplicate." : error.localizedDescription }
            isSending = false
        }
    }
}
