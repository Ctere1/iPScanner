import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled.righthalf.striped.horizontal"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct iPScannerApp: App {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("iPScanner.appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About iPScanner") {
                    showCustomAboutPanel()
                }
            }
            CommandGroup(replacing: .help) {
                Button("iPScanner Help") { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: .command)
                Divider()
                Button("iPScanner on GitHub") {
                    if let url = URL(string: "https://github.com/canberkys/iPScanner") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Report an Issue…") { openWindow(id: "feedback") }
                Divider()
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .iPScannerCommandCheckForUpdates, object: nil)
                }
                Divider()
                Menu("Advanced") {
                Button("Open Vendor Database in Finder") {
                    if let url = Bundle.main.url(forResource: "vendors", withExtension: "json") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Rescan") {
                    NotificationCenter.default.post(name: .iPScannerCommandRescan, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Open Scan…") {
                    NotificationCenter.default.post(name: .iPScannerCommandOpenSnapshot, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Save Scan…") {
                    NotificationCenter.default.post(name: .iPScannerCommandSaveSnapshot, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Divider()

                Button("Compare to Scan…") {
                    NotificationCenter.default.post(name: .iPScannerCommandCompareSnapshot, object: nil)
                }
                Button("Clear Comparison") {
                    NotificationCenter.default.post(name: .iPScannerCommandClearComparison, object: nil)
                }
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export as CSV…") {
                    NotificationCenter.default.post(name: .iPScannerCommandExportCSV, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
                Button("Export as JSON…") {
                    NotificationCenter.default.post(name: .iPScannerCommandExportJSON, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        Settings { ScannerSettingsView() }
        Window("iPScanner Help", id: "help") { ProductHelpView() }
        Window("Feedback", id: "feedback") { FeedbackView() }
            .windowResizability(.contentSize)
    }
}

@MainActor
private func showCustomAboutPanel() {
    let credits = NSMutableAttributedString()
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.labelColor
    ]
    let linkAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.linkColor,
        .link: URL(string: "https://github.com/canberkys/iPScanner") as Any
    ]

    credits.append(NSAttributedString(
        string: "A native macOS network scanner.\nMIT License.\n\n",
        attributes: bodyAttrs
    ))
    credits.append(NSAttributedString(
        string: "github.com/canberkys/iPScanner",
        attributes: linkAttrs
    ))
    credits.append(NSAttributedString(
        string: "\n\nVendor data from IEEE OUI registry.\nBuilt with SwiftUI · Zero third-party dependencies.",
        attributes: bodyAttrs
    ))

    // Read from the bundle instead of a literal so this panel can't drift from
    // the version CI actually shipped (release.yml syncs MARKETING_VERSION
    // from the git tag at build time).
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "iPScanner",
        .applicationVersion: version,
        .credits: credits,
        .init(rawValue: "Copyright"): "© 2026 Canberk Kılıçarslan"
    ])
    NSApp.activate(ignoringOtherApps: true)
}

extension Notification.Name {
    static let iPScannerCommandRescan = Notification.Name("iPScanner.command.rescan")
    static let iPScannerCommandExportCSV = Notification.Name("iPScanner.command.exportCSV")
    static let iPScannerCommandExportJSON = Notification.Name("iPScanner.command.exportJSON")
    static let iPScannerCommandOpenSnapshot = Notification.Name("iPScanner.command.openSnapshot")
    static let iPScannerCommandSaveSnapshot = Notification.Name("iPScanner.command.saveSnapshot")
    static let iPScannerCommandCompareSnapshot = Notification.Name("iPScanner.command.compareSnapshot")
    static let iPScannerCommandClearComparison = Notification.Name("iPScanner.command.clearComparison")
    static let iPScannerCommandCheckForUpdates = Notification.Name("iPScanner.command.checkForUpdates")
}
