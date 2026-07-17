import SwiftUI

// MARK: - Update check overlay

struct UpdateCheckOverlay: ViewModifier {
    let updateChecker: UpdateChecker
    @Binding var lastCheckEpoch: Double
    @Binding var skippedVersion: String
    @Binding var manualOutcome: ContentView.ManualCheckOutcome?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandCheckForUpdates)) { _ in
                handleManualCheck()
            }
            .task {
                let last = lastCheckEpoch > 0 ? Date(timeIntervalSince1970: lastCheckEpoch) : nil
                let timestamp = await updateChecker.autoCheckIfNeeded(lastCheckAt: last)
                lastCheckEpoch = timestamp.timeIntervalSince1970
            }
            .alert(
                "Update available",
                isPresented: alertBinding,
                presenting: updateChecker.availableUpdate
            ) { update in
                Button("View Release") {
                    NSWorkspace.shared.open(update.releaseURL)
                    updateChecker.clearAvailableUpdate()
                }
                Button("Skip This Version") {
                    skippedVersion = update.latestVersion
                    updateChecker.clearAvailableUpdate()
                }
                Button("Later", role: .cancel) {
                    updateChecker.clearAvailableUpdate()
                }
            } message: { update in
                Text("iPScanner \(update.latestVersion) is available. You're on \(update.currentVersion).")
            }
            .alert(item: $manualOutcome, content: outcomeAlert)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: {
                guard let update = updateChecker.availableUpdate else { return false }
                return update.latestVersion != skippedVersion
            },
            set: { newValue in
                if !newValue { updateChecker.clearAvailableUpdate() }
            }
        )
    }

    private func handleManualCheck() {
        Task {
            await updateChecker.checkForUpdates()
            lastCheckEpoch = Date().timeIntervalSince1970
            if updateChecker.availableUpdate == nil {
                if let err = updateChecker.lastError {
                    manualOutcome = .failed(err)
                } else {
                    manualOutcome = .upToDate
                }
            } else {
                skippedVersion = ""
            }
        }
    }

    private func outcomeAlert(_ outcome: ContentView.ManualCheckOutcome) -> Alert {
        switch outcome {
        case .upToDate:
            return Alert(
                title: Text("No updates available"),
                message: Text("You're on the latest version (\(UpdateChecker.currentVersion()))."),
                dismissButton: .default(Text("OK"))
            )
        case .failed(let message):
            return Alert(
                title: Text("Update check failed"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
