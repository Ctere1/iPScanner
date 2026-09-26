import SwiftUI

extension ContentView {
    @ViewBuilder
    var emptyState: some View {
        if let error = controller.lastError {
            ContentUnavailableView {
                Label("Could not scan", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
                Text("Use an IP such as 192.168.1.10 or a subnet such as 192.168.1.0/24.").font(.caption)
            } actions: {
                Button("Troubleshooting") { openWindow(id: "help") }
            }
        } else if controller.isScanning {
            ContentUnavailableView {
                Label("Looking for devices", systemImage: "network")
            } description: {
                Text("Results appear as devices respond. You can stop the scan at any time.")
            }
        } else if case .done = controller.state {
            ContentUnavailableView {
                Label("No devices found", systemImage: "network.slash")
            } description: {
                Text("Check your network and VPN connection. Try Standard if Quick did not find devices; some devices do not respond to discovery.")
            } actions: {
                Button("Scan Again") { controller.start() }.disabled(!controller.canStart)
                Button("Troubleshooting") { openWindow(id: "help") }
            }
        } else if case .stopped = controller.state {
            ContentUnavailableView {
                Label("Scan stopped", systemImage: "stop.circle")
            } description: {
                Text("No results were collected before the scan stopped.")
            } actions: {
                Button("Scan Again") { controller.start() }.disabled(!controller.canStart)
            }
        } else {
            ContentUnavailableView {
                Label("Discover your network", systemImage: "network")
            } description: {
                VStack(spacing: 8) {
                    if let imported = controller.importedTargets {
                        Text("Ready to scan \(imported.targets.count) imported targets")
                    } else if !controller.rangeInput.isEmpty {
                        Text(controller.rangeInput).monospaced()
                    }
                    Text("Choose a network above or enter an IP or subnet. Use Tools to import a target file.")
                    Text("\(controller.profile.label) · Press Scan or ⌘R").font(.caption)
                }
            } actions: {
                Button("Getting Started") { openWindow(id: "help") }
            }
        }
    }
}
