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
                // Both were hardcoded to upstream. This build's update check has always pointed at
                // whatever iPScannerUpdateRepository names, so a fork's "Report an Issue…" opened a
                // bug report against code its maintainer does not have.
                Button("iPScanner on GitHub") {
                    if let url = UpdateChecker.repositoryURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Report an Issue…") {
                    if let url = UpdateChecker.newIssueURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .iPScannerCommandCheckForUpdates, object: nil)
                }
                Divider()
                Button("Open OUI Database in Finder") {
                    if let url = Bundle.main.url(forResource: "oui", withExtension: "txt") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            CommandGroup(after: .pasteboard) {
                Divider()
                // ⇧⌘C, not ⌘C. The old handler was an invisible zero-size button in the toolbar
                // with a window-scoped ⌘C, so copying text out of the search or label field
                // silently copied the selected IPs instead.
                Button("Copy IP Addresses") {
                    NotificationCenter.default.post(name: .iPScannerCommandCopyIPs, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                // ⌘F was documented in a code comment but never actually wired to anything.
                Button("Find") {
                    NotificationCenter.default.post(name: .iPScannerCommandFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                // No Inspector toggle. Host details are a sheet opened by double-clicking a row, so
                // there is no such thing as the panel being "visible" independently of a host — a
                // toggle here would have been a checkbox for a state that no longer exists.
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

@MainActor
private func showCustomAboutPanel() {
    // AppKit centres the name, version and copyright it draws itself, but `credits` is handed over
    // as an attributed string and keeps whatever alignment it carries — which is left by default.
    // So the one block this app supplies was the one block out of line with the panel around it.
    let centred = NSMutableParagraphStyle()
    centred.alignment = .center

    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: centred
    ]
    let linkAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.linkColor,
        .link: UpdateChecker.repositoryURL as Any,
        .paragraphStyle: centred
    ]

    let credits = NSMutableAttributedString()
    credits.append(NSAttributedString(
        string: "A native macOS network scanner.\n\n",
        attributes: bodyAttrs
    ))
    credits.append(NSAttributedString(
        string: "github.com/\(UpdateChecker.repository)",
        attributes: linkAttrs
    ))
    credits.append(NSAttributedString(
        string: "\n\nVendor data from IEEE OUI registry.\nBuilt with SwiftUI · Zero third-party dependencies.",
        attributes: bodyAttrs
    ))

    var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
    options[.applicationVersion] = UpdateChecker.currentVersion()
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
        options[.applicationName] = name
    }
    if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
        options[.init(rawValue: "Copyright")] = copyright
    }

    NSApp.orderFrontStandardAboutPanel(options: options)
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
    static let iPScannerCommandFind = Notification.Name("iPScanner.command.find")
    static let iPScannerCommandCopyIPs = Notification.Name("iPScanner.command.copyIPs")
}
