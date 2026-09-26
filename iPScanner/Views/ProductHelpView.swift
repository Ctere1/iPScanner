import SwiftUI

struct ProductHelpView: View {
    @State private var selection = "Getting Started"
    private let topics: [(String, String, String)] = [
        ("Getting Started", "play.circle", "Choose your network from the globe menu, keep Standard selected in Options, then press Scan. Results appear as devices respond.\n\nYou can enter a single IP (192.168.1.10), a subnet (192.168.1.0/24), or a range (192.168.1.10-192.168.1.50). Tools → Import Targets accepts text or CSV files. An imported file replaces the target field until you remove it.\n\nScan networks you own or have permission to inspect."),
        ("Scan Profiles", "slider.horizontal.3", "Quick uses ping and is best for a fast check. Devices that block ping may be missed.\n\nStandard adds TCP discovery and is the recommended starting point.\n\nDeep also scans ports and reads service banners. It takes longer. Stop ends the active scan, including ports and banners.\n\nAutomatic rescan in Options waits until every stage finishes before starting its countdown."),
        ("Results & Details", "tablecells", "Search by address, hostname, vendor, label or tag. Use Filters to narrow the list and Columns to choose visible information.\n\nSelect a device and click the details button, or press ⌘⌥I. Details open beside the table in wide windows and in a sheet in compact windows.\n\nRight-click a device for connection, copy and diagnostic actions. An open port identifies a reachable service; it is not a security assessment."),
        ("Save & Compare", "doc.on.doc", "File → Save Scan stores a snapshot you can reopen later. File → Compare to Scan compares the current results with a saved snapshot.\n\nUse Export above the results for CSV, JSON, text reports or IP:Port lists. Review exported network information before sharing it.\n\nThe star beside the target saves a range. Show the sidebar to return to saved networks."),
        ("Troubleshooting", "wrench.and.screwdriver", "No devices found? Check that the selected subnet matches your active Wi-Fi or Ethernet network. A VPN may change the route. Try Standard if Quick returns nothing.\n\nSome devices block discovery probes; no response does not prove a device is offline. Names and MAC addresses may be unavailable across routed networks. macOS 27 can additionally restrict MAC access to signed apps with the Network Topology Observation capability; local network permission alone may not be enough. Locally administered MAC addresses do not identify a manufacturer. Device types are estimates; their evidence appears in device details.\n\nIf macOS requests local network access, allow it to scan your network. Review any scan warnings for more detail.\n\nFor a repeatable problem, use Help → Report an Issue… and describe the steps and expected result."),
        ("Keyboard Shortcuts", "keyboard", "⌘R — Scan again\n⌘. — Stop\n⌘O — Open a saved scan\n⌘⌥S — Save a scan\n⌘S — Export CSV\n⌘⇧S — Export JSON\n⌘⌥I — Toggle device details\n⌘, — Settings"),
        ("Updates & Privacy", "arrow.down.circle", "iPScanner can check GitHub Releases for updates when launched, at most once every 24 hours. Change this in Settings. Manual checks remain available in Help and Settings.\n\nA new version opens its GitHub release page for review and download. Updates are not installed automatically.\n\nThere is no telemetry. Send Feedback sends the previewed text and optional environment information through Cloudflare to create a PUBLIC GitHub issue. No GitHub account is required. Scan results, IP addresses and MAC addresses are not attached automatically."),
        ("What's New", "sparkles", "Version 1.3.0\n\n• Fixed the packaging collision that prevented version 1.2.0 from opening.\n• Simplified scanning controls and made device details optional.\n• Unified Stop across discovery, ports and banners.\n• Improved vendor lookup performance.\n• Added in-app help, feedback previews and Settings.")
    ]
    var body: some View {
        HStack(spacing: 0) {
            List(topics, id: \.0, selection: $selection) { topic in
                Label(topic.0, systemImage: topic.1).tag(topic.0)
            }.frame(width: 205)
            Divider()
            ScrollView {
                if let topic = topics.first(where: { $0.0 == selection }) {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(topic.0, systemImage: topic.1).font(.title2.bold())
                        Text(topic.2).textSelection(.enabled).lineSpacing(5)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                }
            }
        }.frame(minWidth: 720, minHeight: 460)
    }
}
