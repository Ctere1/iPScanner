import SwiftUI

struct ScannerSettingsView: View {
    @AppStorage("iPScanner.scanProfile") private var profile = ScanProfile.standard.rawValue
    @AppStorage("iPScanner.appearance") private var appearance = AppearanceMode.system.rawValue
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Form {
            Section("Scanning") {
                Picker("Default profile", selection: $profile) {
                    ForEach(ScanProfile.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text((ScanProfile(rawValue: profile) ?? .standard).description).font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.setAutomaticChecks($0) }
                ))
                Text("Checks the GitHub update feed daily while the app is running. Review release notes, then download and install signed updates from the update window.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Installed version", value: UpdateChecker.currentVersion())
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                if let error = updater.startupError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }.formStyle(.grouped).frame(width: 500, height: 475)
    }
}
