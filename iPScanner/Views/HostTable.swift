import SwiftUI

/// The host table.
struct HostTable: View {
    @Bindable var controller: ScanController
    let columns: ColumnVisibility
    let mdns: MDNSDiscovery
    let rows: [Host]
    let requestPortScan: (Set<Host.ID>) -> Void
    let requestBulkDelete: (Set<Host.ID>) -> Void
    /// Double-click. Inspecting the row is the safe, reversible thing to do with it; opening a
    /// browser is one item down the context menu for anyone who wants it.
    let inspect: (Host.ID) -> Void

    private func highlighted(_ source: String) -> AttributedString {
        HostCellFormatter.highlighted(source, query: controller.searchQuery)
    }

    private var rttTtlHeader: String {
        HostCellFormatter.rttTtlHeader(showRTT: columns.isVisible(.rtt), showTTL: columns.isVisible(.ttl))
    }

    var body: some View {
        Table(rows, selection: $controller.selection, sortOrder: $controller.sortOrder) {
            TableColumn("●") { host in
                Circle()
                    .fill(host.status == .alive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .help(statusLabel(host))
                    .accessibilityLabel(statusLabel(host))
            }
            .width(20)

            TableColumn("IP", value: \.ipNumeric) { host in
                let kind = host.deviceType
                HStack(spacing: 6) {
                    Image(systemName: kind.sfSymbol)
                        .font(.caption)
                        .foregroundStyle(kind == .unknown ? Color.secondary.opacity(0.4) : Color.secondary)
                        .help(kind.label)
                        .frame(width: 14, alignment: .center)
                    Text(highlighted(host.ip)).monospaced()
                }
            }
            .width(min: 130, ideal: 145)

            if controller.diff != nil {
                TableColumn("Δ") { host in
                    if let change = controller.change(for: host) {
                        Image(systemName: change.sfSymbol)
                            .foregroundStyle(change.tint)
                            .help(change.label)
                            .accessibilityLabel(change.label)
                    } else {
                        Text("")
                    }
                }
                .width(20)
            }

            // Not sortable: a label lives on the controller, keyed by anchor, not on `Host` —
            // so there is no key path for `TableColumn(_:value:)` to sort by.
            if columns.isVisible(.label) {
                TableColumn("Label") { host in
                    if let label = controller.label(for: host) {
                        Text(highlighted(label))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(label)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 130)
            }

            if columns.isVisible(.hostname) {
                TableColumn("Hostname", value: \.hostnameSort) { host in
                    if let name = mdns.resolvedName(for: host) {
                        HStack(spacing: 4) {
                            Text(highlighted(name.value))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(name.value)
                            if let badge = name.source.badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.secondary)
                                    .help(name.source.explanation)
                            }
                        }
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .width(min: 110, ideal: 190)
            }

            if columns.isVisible(.mac) {
                TableColumn("MAC", value: \.macSort) { host in
                    if let mac = host.mac {
                        Text(highlighted(mac.uppercased())).monospaced().lineLimit(1)
                    } else {
                        Text("—").monospaced().foregroundStyle(.secondary)
                    }
                }
                .width(min: 120, ideal: 140)
            }

            if columns.isVisible(.vendor) {
                TableColumn("Vendor", value: \.vendorSort) { host in
                    if let vendor = host.vendor {
                        Text(highlighted(vendor))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(vendor)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .width(min: 100, ideal: 150)
            }

            if columns.isVisible(.title) {
                TableColumn("Title", value: \.titleSort) { host in
                    if let title = host.serviceTitle {
                        Text(highlighted(title))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(title)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 130)
            }

            // RTT and TTL share one column, and so it cannot be sortable: `TableColumn(_:value:)`
            // takes a single key path, and this cell shows whichever of the two is enabled.
            // Splitting them would fix that, but takes the table to 11 columns — one past
            // `TableColumnBuilder`'s limit — and wrapping in `Group` to get under it defeats the
            // type-checker on an expression this size. Left merged deliberately.
            if columns.isVisible(.rtt) || columns.isVisible(.ttl) {
                TableColumn(rttTtlHeader) { host in
                    Text(HostCellFormatter.rttTtlCell(
                        host,
                        showRTT: columns.isVisible(.rtt),
                        showTTL: columns.isVisible(.ttl)
                    ))
                    .monospaced()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .help(HostCellFormatter.ttlHint(for: host.ttl))
                }
                .width(min: 60, ideal: 90, max: 140)
            }

            if columns.isVisible(.ports) {
                TableColumn("Ports", value: \.openPortCount) { host in
                    Text(PortScanner.displayList(open: host.openPorts, scanned: host.scannedPorts))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(host.scannedPorts.isEmpty ? .secondary : .primary)
                        .help(HostCellFormatter.portsHelp(for: host))
                }
                .width(min: 80, ideal: 140)
            }
        }
        .frame(maxHeight: .infinity)
        .contextMenu(forSelectionType: Host.ID.self) { ids in
            HostContextMenu(
                controller: controller,
                ids: ids,
                requestPortScan: requestPortScan,
                requestBulkDelete: requestBulkDelete
            )
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first else { return }
            inspect(id)
        }
    }

    private func statusLabel(_ host: Host) -> String {
        switch host.status {
        case .alive: "Alive"
        case .dead: "Dead"
        case .scanning: "Scanning"
        }
    }
}
