import SwiftUI

/// The table's right-click menu, for one host or for a selection.
struct HostContextMenu: View {
    let controller: ScanController
    let ids: Set<Host.ID>
    /// Asking rather than setting: the sheet's presentation state belongs to the view that owns
    /// the sheet, and the request also has to clear the previous run's port error.
    let requestPortScan: (Set<Host.ID>) -> Void
    let requestBulkDelete: (Set<Host.ID>) -> Void

    private var hosts: [Host] {
        ids.compactMap { id in controller.hosts.first { $0.id == id } }
    }

    var body: some View {
        if ids.count == 1, let host = hosts.first {
            singleHostMenu(host)
        } else if ids.count > 1 {
            multiHostMenu
        }
    }

    // MARK: - Single

    @ViewBuilder
    private func singleHostMenu(_ h: Host) -> some View {
        Section {
            Button("Open in Browser (http)", systemImage: "safari") {
                HostActions.openBrowser(ip: h.ip)
            }
            Button("Open in Browser (https)", systemImage: "lock.shield") {
                HostActions.openBrowser(ip: h.ip, scheme: "https")
            }
            Button("SSH in Terminal", systemImage: "terminal") {
                HostActions.openSSH(ip: h.ip)
            }
            Button("Connect via VNC", systemImage: "rectangle.connected.to.line.below") {
                HostActions.openVNC(ip: h.ip)
            }
            Button("Microsoft Remote Desktop (RDP)", systemImage: "display") {
                HostActions.openRDP(ip: h.ip)
            }
            Button("Open SMB Share", systemImage: "externaldrive.connected.to.line.below") {
                HostActions.openSMB(ip: h.ip)
            }
            Button("Open AFP Share", systemImage: "externaldrive") {
                HostActions.openAFP(ip: h.ip)
            }
            Button("Telnet in Terminal", systemImage: "terminal.fill") {
                HostActions.openTelnet(ip: h.ip)
            }
            Button("Ping in Terminal", systemImage: "wave.3.right") {
                HostActions.pingInTerminal(ip: h.ip)
            }
        }
        Section {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await controller.refreshHost(h.id) }
            }
            if h.mac != nil {
                Button("Wake (Wake-on-LAN)", systemImage: "power.circle.fill") {
                    Task { await controller.runWakeOnLAN(for: [h.id]) }
                }
            }
            Button("Port Scan…", systemImage: "network.badge.shield.half.filled") {
                requestPortScan([h.id])
            }
        }
        Section {
            Button("Copy IP", systemImage: "doc.on.doc") { HostActions.copy(h.ip) }
            if let hostname = h.hostname {
                Button("Copy Hostname") { HostActions.copy(hostname) }
            }
            if let mac = h.mac {
                Button("Copy MAC") { HostActions.copy(mac) }
            }
        }
        Section {
            Button("Remove from List", systemImage: "trash", role: .destructive) {
                controller.deleteHosts([h.id])
            }
        }
    }

    // MARK: - Multi

    @ViewBuilder
    private var multiHostMenu: some View {
        let selected = hosts
        let wakeable = selected.filter { $0.mac != nil }.count

        Button("Refresh (\(selected.count) hosts)", systemImage: "arrow.clockwise") {
            Task { await controller.refreshHosts(ids) }
        }
        Button("Port Scan… (\(selected.count) hosts)", systemImage: "network.badge.shield.half.filled") {
            requestPortScan(ids)
        }
        if wakeable > 0 {
            Button("Wake (\(wakeable) hosts)", systemImage: "power.circle.fill") {
                Task { await controller.runWakeOnLAN(for: ids) }
            }
        }
        Button("Copy IPs", systemImage: "doc.on.doc") {
            HostActions.copy(selected.map(\.ip).joined(separator: "\n"))
        }
        Section {
            // Confirmed because it is irreversible and bulk: there is no undo, and misclicking it
            // with a large selection silently discards a whole scan's worth of rows. The
            // single-host version stays unconfirmed — one row is cheap to get back.
            Button("Remove from List (\(selected.count) hosts)", systemImage: "trash", role: .destructive) {
                requestBulkDelete(ids)
            }
        }
    }
}
