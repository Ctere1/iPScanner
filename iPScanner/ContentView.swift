import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var controller = ScanController()
    @State private var mdns = MDNSDiscovery()
    /// Carries the hosts to scan, captured when the menu item was clicked.
    ///
    /// A sheet, not a popover: the trigger is often a context menu or the overflow menu, neither of
    /// which has an on-screen anchor — the old popover had exactly one anchor, in a toolbar group
    /// that only renders at full width, so at any narrower layout "Port Scan…" did nothing at all.
    @State private var portScanRequest: PortScanRequest?
    @State private var pendingBulkDelete: BulkDeleteRequest?
    @State private var portsInput = PortScanner.defaultPortsInput
    @State private var portError: String?
    @State private var fetchBanners = true
    @State private var renamingRange: SavedRange?
    @State private var importAlert: ImportAlert?
    @State private var showingSubnetCalc = false
    @State private var subnetCalcInput = ""
    @State private var updateChecker = UpdateChecker()
    @State private var manualCheckOutcome: ManualCheckOutcome?
    @AppStorage("iPScanner.update.lastCheckAt") private var updateLastCheckEpoch: Double = 0
    @AppStorage("iPScanner.update.skippedVersion") private var updateSkippedVersion: String = ""
    @FocusState private var searchFieldFocused: Bool

    /// Saving and copying the table. The file I/O used to live in this view.
    private var exporter: ExportCoordinator { ExportCoordinator(controller: controller) }

    /// Reading and writing .ipscan.json files. The panels and decoding used to live in this view.
    private var snapshots: SnapshotFileCoordinator { SnapshotFileCoordinator(controller: controller) }

    enum ManualCheckOutcome: Identifiable {
        case upToDate
        case failed(String)
        var id: String {
            switch self {
            case .upToDate: "upToDate"
            case .failed(let msg): "failed-\(msg)"
            }
        }
    }

    struct BulkDeleteRequest: Identifiable {
        let id = UUID()
        let ids: Set<Host.ID>
    }

    struct PortScanRequest: Identifiable {
        let id = UUID()
        /// Explicit, because `runPortScan` defaults to the current selection — which meant
        /// right-clicking an unselected row scanned the selected hosts instead of that row.
        let targets: Set<Host.ID>
    }

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // Column visibility (persisted) — Status, Device icon, IP always visible.
    @State private var columns = ColumnVisibility()

    @AppStorage("iPScanner.inspectorWidth") private var inspectorWidth: Double = 320
    @AppStorage("iPScanner.inspectorVisible") private var inspectorVisible = true
    @AppStorage("iPScanner.scanProfile") private var profileRaw: String = ScanProfile.standard.rawValue
    @AppStorage("iPScanner.rescanInterval") private var rescanIntervalRaw: String = RescanInterval.off.rawValue

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { controller.alert != nil },
            set: { if !$0 { controller.dismissAlert() } }
        )
    }

    private var bulkDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingBulkDelete != nil },
            set: { if !$0 { pendingBulkDelete = nil } }
        )
    }

    private var profileBinding: Binding<ScanProfile> {
        Binding(
            get: { ScanProfile(rawValue: profileRaw) ?? .standard },
            set: { newValue in
                profileRaw = newValue.rawValue
                controller.profile = newValue
            }
        )
    }

    private var rescanBinding: Binding<RescanInterval> {
        Binding(
            get: { RescanInterval(rawValue: rescanIntervalRaw) ?? .off },
            set: { newValue in
                rescanIntervalRaw = newValue.rawValue
                controller.rescanInterval = newValue
            }
        )
    }

    /// Resolved against `filteredHosts`, not `hosts`.
    ///
    /// Against `hosts`, filtering out the selected row left the inspector open showing a host that
    /// was no longer in the table — and since ⌘-clicking the row was the only way to deselect, the
    /// panel was stuck with no way out. Selection itself is deliberately left alone: the Table
    /// remembers it, so clearing the filter brings back both the row and the panel.
    private var inspectedHost: Host? {
        guard controller.selection.count == 1,
              let id = controller.selection.first else { return nil }
        return controller.filteredHosts.first { $0.id == id }
    }

    /// The inspector was purely a shadow of selection, so there was nothing to close — no button,
    /// no Escape, no menu item. Now it has its own visibility, and selecting a host only opens it
    /// if the user hasn't hidden it. Sticky, like Xcode's inspector.
    private var showInspector: Bool { inspectorVisible && inspectedHost != nil }

    // `body` is split into three expressions on purpose: as one chain — the layout plus ten
    // notification handlers plus every sheet, alert and dialog — it grew past what the Swift
    // type-checker will solve, and the build failed with "unable to type-check in reasonable time".
    var body: some View {
        presentations(commandHandlers(rootLayout))
    }

    private var rootLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    content
                    Divider()
                    StatusBar(controller: controller)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Escape means "clear the selection" in a table; the inspector closing is the
                // consequence, not the goal. Previously there was no Escape handling at all.
                .onExitCommand {
                    if !controller.selection.isEmpty { controller.selection = [] }
                }

                // `showInspector` already proves the host exists, so this is not an optional dance:
                // HostInspector takes a real Host and its dead "Select a host" placeholder is gone.
                if showInspector, let host = inspectedHost {
                    ResizableDivider(width: $inspectorWidth, minWidth: 260, maxWidth: 460)
                    HostInspector(
                        host: host,
                        label: controller.label(for: host),
                        anchor: controller.anchor(for: host),
                        services: mdns.services(for: host.ip),
                        resolvedName: mdns.resolvedName(for: host),
                        onClose: { inspectorVisible = false },
                        // Keyed by the anchor captured when editing began, not by whatever is
                        // selected when the commit lands — see HostInspector.
                        onLabelChange: { anchor, newValue in
                            controller.setLabel(newValue, forAnchor: anchor)
                        }
                    )
                    .frame(width: inspectorWidth)
                }
            }
            .navigationSplitViewColumnWidth(min: 720, ideal: 1100)
        }
        .frame(minWidth: 960, minHeight: 540)
        .onAppear {
            controller.profile = ScanProfile(rawValue: profileRaw) ?? .standard
            controller.rescanInterval = RescanInterval(rawValue: rescanIntervalRaw) ?? .off
            controller.detectDefaultSubnetIfNeeded()
            mdns.start()
        }
    }

    /// App-menu commands arrive as notifications (the pattern iPScannerApp already uses).
    @ViewBuilder
    private func commandHandlers<V: View>(_ content: V) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandRescan)) { _ in
            if !controller.isScanning { controller.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandExportCSV)) { _ in
            if !controller.hosts.isEmpty { exporter.save(.csv) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandExportJSON)) { _ in
            if !controller.hosts.isEmpty { exporter.save(.json) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandOpenSnapshot)) { _ in
            openSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandSaveSnapshot)) { _ in
            if !controller.hosts.isEmpty { saveSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandCompareSnapshot)) { _ in
            openComparisonBaseline()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandClearComparison)) { _ in
            controller.clearComparison()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandFind)) { _ in
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandCopyIPs)) { _ in
            exporter.copySelectedIPs()
        }
    }

    @ViewBuilder
    private func presentations<V: View>(_ content: V) -> some View {
        content
        .modifier(UpdateCheckOverlay(
            updateChecker: updateChecker,
            lastCheckEpoch: $updateLastCheckEpoch,
            skippedVersion: $updateSkippedVersion,
            manualOutcome: $manualCheckOutcome
        ))
        .sheet(item: $renamingRange) { saved in
            RenameRangeSheet(
                range: saved.range,
                initialName: saved.name ?? ""
            ) { newName in
                controller.renameSavedRange(saved.range, to: newName)
            }
        }
        .alert(
            controller.alert?.title ?? "",
            isPresented: alertPresented,
            presenting: controller.alert
        ) { _ in
            Button("OK", role: .cancel) { controller.dismissAlert() }
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            "Remove \(pendingBulkDelete?.ids.count ?? 0) hosts from the list?",
            isPresented: bulkDeletePresented,
            presenting: pendingBulkDelete
        ) { request in
            Button("Remove", role: .destructive) {
                controller.deleteHosts(request.ids)
                pendingBulkDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingBulkDelete = nil }
        } message: { _ in
            Text("They'll reappear on the next scan. Labels are kept.")
        }
        .sheet(item: $portScanRequest) { request in
            portScanSheet(request)
        }
        .alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List {
            Section("Saved Ranges") {
                if controller.savedRanges.isEmpty {
                    Text("No ranges yet.\nUse the ☆ next to the range field to save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(controller.savedRanges) { saved in
                        savedRangeRow(saved)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func savedRangeRow(_ saved: SavedRange) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .foregroundStyle(.tint)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                if let name = saved.name, !name.isEmpty {
                    Text(name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(saved.range)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(saved.range)
                        .font(.callout)
                        .monospaced()
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                controller.removeSavedRange(saved.range)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove this range")
            .accessibilityLabel("Remove this range")
        }
        .contentShape(.rect)
        .onTapGesture {
            controller.loadSavedRange(saved.range)
        }
        .contextMenu {
            Button("Rename…", systemImage: "pencil") {
                renamingRange = saved
            }
            Button("Remove", systemImage: "trash", role: .destructive) {
                controller.removeSavedRange(saved.range)
            }
        }
    }

    private func host(forID id: Host.ID) -> Host? {
        controller.hosts.first { $0.id == id }
    }

    /// Explains where a Ports cell's value came from.
    ///
    /// The column is legitimately mixed under the Standard profile: a host that answered ICMP was
    /// never port-probed and reads "—", while one found via the TCP fallback shows the handful of
    /// ports discovery already tried. Without this the two look like the same column disagreeing
    /// with itself.
    /// Reverse DNS first, then the names the scan picked up elsewhere. Most LANs have no PTR
    /// records, so without the fallbacks this column reads "—" for every host even when the device
    /// is announcing its name over Bonjour.
    // MARK: - Toolbar

    /// How much of the toolbar is shown inline; the rest moves to the overflow menu.
    ///
    /// Laid out flat the controls need roughly 900pt, but the detail pane only gets what is left
    /// after the sidebar and inspector take theirs. Selecting a host opens the 320pt inspector and
    /// leaves the table pane around 390pt — so there are three genuinely different widths to
    /// serve, not two, and a two-step ladder still overflowed the moment a row was selected.
    ///
    /// Controls that cannot shrink (a segmented picker, `.fixedSize()` menus) must be *removed* at
    /// narrow widths rather than squeezed: an HStack that cannot shrink does not clip, it overflows
    /// and draws over its neighbours.
    private enum ToolbarDensity {
        case full     // everything inline
        case compact  // secondary controls in the overflow menu
        case tight    // inspector is open: range, scan, progress, search, overflow
        case minimal  // inspector dragged wide: range, scan, overflow — nothing optional left
    }

    @ViewBuilder
    private var toolbar: some View {
        // ViewThatFits falls back to the *last* child when none fit, so `.minimal` must be the
        // smallest layout that is still usable: dragging the inspector out to its 460pt maximum
        // leaves the table pane around 254pt, narrower than even `.tight` needs.
        ViewThatFits(in: .horizontal) {
            toolbarRow(.full)
            toolbarRow(.compact)
            toolbarRow(.tight)
            toolbarRow(.minimal)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func toolbarRow(_ density: ToolbarDensity) -> some View {
        HStack(spacing: 10) {
            targetControls(density)
            scanControls(density)
            if density == .full {
                actionControls
            }
            Spacer(minLength: 8)
            if density == .full {
                viewControls
            } else {
                searchField(density)
                overflowMenu
            }
        }
    }

    /// Secondary controls, folded into one menu when the row is too narrow to show them inline.
    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            Picker("Profile", selection: profileBinding) {
                ForEach(ScanProfile.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.inline)
            .disabled(controller.isScanning)

            Picker("Auto-rescan", selection: rescanBinding) {
                ForEach(RescanInterval.allCases) { i in
                    Text(i.menuLabel).tag(i)
                }
            }
            .pickerStyle(.inline)

            if !controller.hosts.isEmpty {
                Divider()
                Button("Port Scan…") {
                    portError = nil
                    portScanRequest = PortScanRequest(targets: controller.selection)
                }
                .disabled(controller.selection.isEmpty || controller.portScanInProgress || controller.isScanning)

                Menu("Export") {
                    ExportMenu(exporter: exporter)
                }

                Divider()
                FilterMenu(controller: controller, includeDeadHosts: true)

                Menu("Columns") { ColumnsMenu(columns: columns) }
            }

            Divider()
            Menu("Interface Subnet") {
                let interfaces = NetworkInterface.scannableInterfaces()
                if interfaces.isEmpty {
                    Text("No active interfaces")
                } else {
                    ForEach(interfaces, id: \.name) { iface in
                        Button("\(iface.name) — \(iface.ipv4)/\(iface.netmaskBits)") {
                            if let subnet = NetworkInterface.subnet(from: iface) {
                                controller.rangeInput = subnet
                            }
                        }
                    }
                }
            }
            Button("Import Targets…") { openTargetFile() }
                .disabled(controller.isScanning)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More controls")
        .accessibilityLabel("More controls")
    }

    /// A text field cannot live in a menu, so search is the one control the minimal row drops
    /// outright rather than folding away — ⌘F is a no-op at that width, and there is nowhere to
    /// put it that would not push something else out.
    @ViewBuilder
    private func searchField(_ density: ToolbarDensity) -> some View {
        if !controller.hosts.isEmpty, density != .minimal {
            TextField("", text: $controller.searchQuery, prompt: Text("Search…"))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: density == .tight ? 70 : 90, maxWidth: 200)
                .focused($searchFieldFocused)
        }
    }

    @ViewBuilder
    private func targetControls(_ density: ToolbarDensity) -> some View {
        HStack(spacing: 10) {
            if let imported = controller.importedTargets {
                importedChip(imported)
            } else {
                TextField("10.0.0.0/24, 192.168.1.0/24, 172.16.5.50-172.16.5.100", text: $controller.rangeInput)
                    .textFieldStyle(.roundedBorder)
                    // Allowed to shrink: it is the one control that can give width back to the row.
                    .frame(minWidth: density == .full || density == .compact ? 130 : 100, maxWidth: 380)
                    .onSubmit { if !controller.isScanning { controller.start() } }

                if density == .full || density == .compact {
                    Button {
                        controller.toggleSaveCurrentRange()
                    } label: {
                        Image(systemName: controller.isCurrentRangeSaved ? "star.fill" : "star")
                            .foregroundStyle(controller.isCurrentRangeSaved ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help(controller.isCurrentRangeSaved ? "Remove from saved" : "Save range")
                    .accessibilityLabel(controller.isCurrentRangeSaved ? "Remove from saved" : "Save range")
                }
            }

            // These three are reachable from the overflow menu at narrower widths.
            if density == .full {
                Button {
                    openTargetFile()
                } label: {
                    Image(systemName: "doc.badge.arrow.up")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Import targets from .txt or .csv")
                .accessibilityLabel("Import targets")
                .disabled(controller.isScanning)
            }

            Button {
                if subnetCalcInput.isEmpty {
                    subnetCalcInput = controller.rangeInput
                }
                showingSubnetCalc.toggle()
            } label: {
                Image(systemName: "function")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Subnet calculator")
            .accessibilityLabel("Subnet calculator")
            // Stays visible at every density. Hiding it with a zero-width frame left the popover
            // anchored to an invisible point, so it opened somewhere unrelated to the click. A
            // popover's trigger has to be the control the user actually pressed.
            .popover(isPresented: $showingSubnetCalc, arrowEdge: .bottom) {
                subnetCalcPopover
            }

            if density == .full {
                Menu {
                let interfaces = NetworkInterface.scannableInterfaces()
                if interfaces.isEmpty {
                    Text("No active interfaces").foregroundStyle(.secondary)
                } else {
                    ForEach(interfaces, id: \.name) { iface in
                        Button {
                            if let subnet = NetworkInterface.subnet(from: iface) {
                                controller.rangeInput = subnet
                            }
                        } label: {
                            Text("\(iface.name) — \(iface.ipv4)/\(iface.netmaskBits)")
                        }
                    }
                }
            } label: {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
            }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Pick interface subnet")
                .accessibilityLabel("Pick interface subnet")
            }
        }
    }

    @ViewBuilder
    private func scanControls(_ density: ToolbarDensity) -> some View {
        HStack(spacing: 10) {
            if controller.isScanning {
                Button("Stop", systemImage: "stop.fill") { controller.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(".", modifiers: [.command])
                    .help("Stop scan (⌘.)")
            } else {
                Button("Scan", systemImage: "play.fill") { controller.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(controller.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Start scan (⌘R)")
            }

            // The segmented picker is pinned at 220pt and cannot shrink below its labels, so it is
            // removed rather than squeezed; the same choice lives in the overflow menu.
            if density == .full {
                Picker("", selection: profileBinding) {
                    ForEach(ScanProfile.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .help(profileBinding.wrappedValue.description)
                .disabled(controller.isScanning)
            }

            if density == .full || density == .compact {
                rescanMenu
            }

            if case .scanning(let scanned, let total) = controller.state {
                ProgressView(value: Double(scanned), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .frame(minWidth: density == .full || density == .compact ? 60 : 40, maxWidth: 160)
            }
        }
    }

    @ViewBuilder
    private var rescanMenu: some View {
        Group {
            Menu {
                Picker("Auto-rescan", selection: rescanBinding) {
                    ForEach(RescanInterval.allCases) { i in
                        Text(i.menuLabel).tag(i)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: rescanBinding.wrappedValue == .off
                          ? "arrow.clockwise"
                          : "arrow.clockwise.circle.fill")
                        .foregroundStyle(rescanBinding.wrappedValue == .off ? Color.secondary : Color.accentColor)
                    if rescanBinding.wrappedValue != .off {
                        Text(rescanBinding.wrappedValue.label)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Auto-rescan interval")
            .accessibilityLabel("Auto-rescan interval")
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: 10) {
            if !controller.hosts.isEmpty {
                Button {
                    portError = nil
                    portScanRequest = PortScanRequest(targets: controller.selection)
                } label: {
                    Label("Port Scan…", systemImage: "network.badge.shield.half.filled")
                }
                .disabled(controller.selection.isEmpty || controller.portScanInProgress || controller.isScanning)
            }

            if controller.portScanInProgress {
                HStack(spacing: 6) {
                    ProgressView(
                        value: Double(controller.portScanProgress.scanned),
                        total: Double(max(controller.portScanProgress.total, 1))
                    )
                    .progressViewStyle(.linear)
                    .frame(minWidth: 50, maxWidth: 100)
                    Text("\(controller.portScanProgress.scanned) / \(controller.portScanProgress.total)")
                        .lineLimit(1)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        controller.cancelPortScan()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Cancel port scan")
                }
            }

            if !controller.hosts.isEmpty {
                Menu {
                    ExportMenu(exporter: exporter)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var viewControls: some View {
        HStack(spacing: 10) {
            if !controller.hosts.isEmpty {
                TextField("", text: $controller.searchQuery, prompt: Text("Search…"))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 90, maxWidth: 200)
                    .focused($searchFieldFocused)

                Menu {
                    FilterMenu(controller: controller)
                } label: {
                    Image(systemName: controller.hasActiveScopeFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(controller.hasActiveScopeFilters ? Color.accentColor : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filters")
                .accessibilityLabel("Filters")

                Toggle("Dead hosts", isOn: $controller.showDeadHosts)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Show unresponsive IPs")

                Menu {
                    ColumnsMenu(columns: columns)
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Show / hide columns")
                .accessibilityLabel("Column visibility")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Subnet calculator popover

    @ViewBuilder
    private var subnetCalcPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subnet calculator")
                .font(.headline)

            TextField("CIDR (e.g. 10.0.0.0/24)", text: $subnetCalcInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { /* recompute is automatic */ }

            if let summary = SubnetCalculator.summarize(subnetCalcInput) {
                VStack(alignment: .leading, spacing: 4) {
                    subnetRow("Network",   summary.network)
                    subnetRow("Broadcast", summary.broadcast)
                    if let first = summary.firstHost, let last = summary.lastHost {
                        subnetRow("Hosts", "\(first) → \(last)")
                    } else {
                        subnetRow("Hosts", "—")
                    }
                    subnetRow("Count",     "\(summary.hostCount) usable")
                    subnetRow("Netmask",   summary.netmask)
                    subnetRow("Wildcard",  summary.wildcard)
                }
                .font(.callout)
                .monospacedDigit()

                HStack {
                    Spacer()
                    Button("Use as scan range") {
                        controller.clearImportedFile()
                        controller.rangeInput = summary.cidr
                        showingSubnetCalc = false
                    }
                    .controlSize(.small)
                    .disabled(controller.isScanning)
                }
            } else if !subnetCalcInput.isEmpty {
                Text("Invalid CIDR. Try `10.0.0.0/24`.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Enter an IPv4 CIDR to see network, broadcast, and host range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private func subnetRow(_ key: String, _ value: String) -> some View {
        // .body and no placeholder: a computed subnet field is never absent, so there is nothing
        // for an em dash to stand in for.
        InfoRow(key: key, value: value, font: .body, placeholder: nil)
    }

    // MARK: - Imported targets chip

    @ViewBuilder
    private func importedChip(_ imported: ScanController.ImportedTargets) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(imported.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(imported.targets.count) target\(imported.targets.count == 1 ? "" : "s")\(imported.invalidLineCount > 0 ? " · \(imported.invalidLineCount) skipped" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                controller.clearImportedFile()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear imported list")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.10))
        )
        .frame(maxWidth: 380, alignment: .leading)
    }

    private func openTargetFile() {
        guard let url = FilePanels.open(
            contentTypes: [.plainText, .commaSeparatedText, .text],
            message: "Select a .txt or .csv file containing IPs, CIDRs, or ranges (one per line; commas allowed)."
        ) else { return }
        do {
            let summary = try controller.loadImportedFile(url: url)
            if summary.invalidLineCount > 0 {
                importAlert = ImportAlert(
                    title: "Imported with skipped lines",
                    message: "\(summary.targetCount) targets parsed. \(summary.invalidLineCount) line\(summary.invalidLineCount == 1 ? "" : "s") could not be parsed and were skipped."
                )
            }
        } catch {
            importAlert = ImportAlert(
                title: "Could not import",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        // Bound once: `filteredHosts` filters *and* sorts the whole list on every read, and the
        // body reads it more than once.
        let rows = controller.filteredHosts
        if controller.hosts.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            // Previously this branch didn't exist: filtering everything out left the table headers
            // above an empty void with nothing to explain it or undo it.
            filteredEmptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HostTable(
                controller: controller,
                columns: columns,
                mdns: mdns,
                rows: rows,
                requestPortScan: { targets in
                    portError = nil
                    portScanRequest = PortScanRequest(targets: targets)
                },
                requestBulkDelete: { pendingBulkDelete = BulkDeleteRequest(ids: $0) }
            )
        }
    }

    private var filteredEmptyState: some View {
        Group {
            if !controller.searchQuery.isEmpty {
                ContentUnavailableView.search(text: controller.searchQuery)
            } else {
                ContentUnavailableView {
                    Label("No matching hosts", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("\(controller.hosts.count) host\(controller.hosts.count == 1 ? " is" : "s are") hidden by the active filters.")
                } actions: {
                    Button("Clear Filters") {
                        controller.clearScopeFilters()
                        controller.showDeadHosts = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let err = controller.lastError {
            ContentUnavailableView {
                Label("iPScanner", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } description: {
                Text(err).foregroundStyle(.red)
            }
        } else {
            let trimmed = controller.rangeInput.trimmingCharacters(in: .whitespaces)
            ContentUnavailableView {
                Label("iPScanner", systemImage: "network")
            } description: {
                if !trimmed.isEmpty {
                    VStack(spacing: 4) {
                        Text("Ready to scan")
                            .foregroundStyle(.secondary)
                        Text(trimmed)
                            .monospaced()
                            .foregroundStyle(.tint)
                        Text("Press Scan or ⌘R")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Enter an IP range and press Scan.")
                }
            }
        }
    }

    // MARK: - Port scan sheet

    @ViewBuilder
    private func portScanSheet(_ request: PortScanRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Port scan for \(request.targets.count) host(s)")
                .font(.headline)

            TextField("Ports", text: $portsInput, prompt: Text("22, 80, 443, 8000-8100"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            Picker("Preset", selection: portPresetBinding) {
                ForEach(PortPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Fetch service banners (HTTP/SSH)", isOn: $fetchBanners)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Query title/banner for hosts with port 80/443/22 open")

            if let estimate = portScanEstimate {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: estimate.isHeavy ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(estimate.isHeavy ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(estimate.hosts) hosts × \(estimate.ports) ports = \(estimate.totalProbes) probes")
                        Text("~\(estimate.estimatedSeconds)s estimated")
                    }
                    .font(.caption)
                    .foregroundStyle(estimate.isHeavy ? .orange : .secondary)
                }
            }

            if let portError {
                Text(portError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { portScanRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Scan") { startPortScan(targets: request.targets) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var portPresetBinding: Binding<PortPreset> {
        Binding(
            get: { PortPreset.matching(portsInput) },
            // .custom has no list of its own — picking it leaves whatever is typed alone.
            set: { if let input = $0.portsInput { portsInput = input } }
        )
    }

    // MARK: - Snapshot save / load

    private func saveSnapshot() { snapshots.save() }

    private func openSnapshot() { snapshots.open() }

    private func openComparisonBaseline() { snapshots.openComparisonBaseline() }

    private struct PortScanEstimate {
        let hosts: Int
        let ports: Int
        let totalProbes: Int
        let estimatedSeconds: Int
        let isHeavy: Bool
    }

    private var portScanEstimate: PortScanEstimate? {
        let hosts = controller.selection.count
        guard hosts > 0,
              let parsed = PortScanner.parsePorts(portsInput) else { return nil }
        let ports = parsed.count
        let total = hosts * ports
        // Controller runs `portScanHostConcurrency` hosts in parallel; each host probes
        // `PortScanner.perHostConcurrency` ports in parallel with ~0.8s timeout per port.
        // Total time ≈ ceil(hosts/H) * ceil(ports/P) * 0.8s.
        let hostBatches = Int(ceil(Double(hosts) / Double(ScanController.portScanHostConcurrency)))
        let portBatches = Int(ceil(Double(ports) / Double(PortScanner.perHostConcurrency)))
        let estimated = max(1, hostBatches * portBatches)
        return PortScanEstimate(
            hosts: hosts,
            ports: ports,
            totalProbes: total,
            estimatedSeconds: estimated,
            isHeavy: total > 50_000 || estimated > 60
        )
    }

    private func startPortScan(targets: Set<Host.ID>) {
        guard let ports = PortScanner.parsePorts(portsInput) else {
            portError = "Invalid port input (e.g. 22, 80, 443 or 8000-8100)"
            return
        }
        if ports.count > 5000 {
            portError = "Too many ports: \(ports.count). Scans over 5000 ports are slow."
            return
        }
        portError = nil
        portScanRequest = nil
        controller.runPortScan(ports: ports, fetchBanners: fetchBanners, targetIds: targets)
    }

    // MARK: - Status bar
}

#Preview {
    ContentView()
        .frame(width: 900, height: 560)
}
