import SwiftUI

struct ScannerSettingsView: View {
    @AppStorage("iPScanner.scanProfile") private var profile = ScanProfile.standard.rawValue
    @AppStorage("iPScanner.appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("iPScanner.update.automatic") private var automatic = true
    @AppStorage("iPScanner.update.lastCheckAt") private var lastCheck: Double = 0
    @State private var checker = UpdateChecker()
    @State private var checked = false

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
                Toggle("Automatically check for updates", isOn: $automatic)
                Text("Checks GitHub when the app opens, at most once every 24 hours. Downloads and installation remain under your control.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Installed version", value: UpdateChecker.currentVersion())
                if lastCheck > 0 {
                    LabeledContent("Last check attempt", value: Date(timeIntervalSince1970: lastCheck).formatted(date: .abbreviated, time: .shortened))
                }
                Button(checker.isChecking ? "Checking…" : "Check for Updates") {
                    Task {
                        await checker.checkForUpdates()
                        lastCheck = Date().timeIntervalSince1970
                        checked = true
                    }
                }.disabled(checker.isChecking)
                if let error = checker.lastError {
                    Text("Could not check for updates. \(error)").font(.caption).foregroundStyle(.orange)
                } else if let update = checker.availableUpdate {
                    Link("View iPScanner \(update.latestVersion) release notes and download", destination: update.releaseURL)
                } else if checked {
                    Text("You’re up to date.").foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped).frame(width: 500, height: 475)
    }
}
