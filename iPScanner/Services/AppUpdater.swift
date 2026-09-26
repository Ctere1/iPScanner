import Combine
import Foundation
import Sparkle

/// One updater for the application, shared by every window and Settings.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var startupError: String?
    private let controller: SPUStandardUpdaterController

    init() {
        // Preserve an explicit old preference; new installs use Sparkle's consent UI.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let old = defaults.object(forKey: "iPScanner.update.automatic") as? Bool {
            defaults.set(old, forKey: "SUEnableAutomaticChecks")
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main).assign(to: &$automaticallyChecks)
        // Unit tests must not start background requests or present permission UI.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do { try controller.updater.start() }
        catch { startupError = "Could not start the updater: \(error.localizedDescription)" }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
