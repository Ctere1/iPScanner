import SwiftUI
import AppKit

struct HostInspector: View {
    /// Non-optional: the caller only builds this when a host is selected, so the old "Select a
    /// host" placeholder branch could never render.
    let host: Host
    let label: String?
    let anchor: String
    let services: [MDNSDiscovery.ServiceRecord]
    /// Best name across DNS/mDNS/NetBIOS. Passed in because only ContentView holds the mDNS index.
    let resolvedName: ResolvedName?
    let onClose: () -> Void
    /// `(anchor, newValue)` — the anchor is passed back so the caller writes to the host that was
    /// being edited rather than re-resolving whatever is selected by the time this fires.
    let onLabelChange: (String, String?) -> Void

    @State private var labelText: String = ""
    @State private var labelSavedAt: Date?
    /// Captured when editing starts. A commit can land after the selection has already moved on —
    /// switching hosts, or the panel closing — and must still name the host it belongs to.
    @State private var editingAnchor: String?
    /// The label as it was when editing started, for the "did it actually change?" test. Comparing
    /// against the live `label` compared against the *new* host's label by commit time.
    @State private var labelSnapshot: String?

    /// Header, scrolling body, footer — the shape of a macOS sheet.
    ///
    /// This was one ScrollView with everything inside it, including the header, which is the shape
    /// of a *sidebar*: the whole panel scrolled as one, so the title slid away with the content and
    /// the only way out was an X in the top corner. As a modal it read as a long strip that had been
    /// cut off rather than a dialog. Now the title stays put, the body scrolls under it, and the way
    /// out is a Done button where a sheet's buttons belong.
    var body: some View {
        VStack(spacing: 0) {
            header(host: host)
                .padding(.horizontal, DesignTokens.Spacing.surface)
                .padding(.top, DesignTokens.Spacing.surface)
                .padding(.bottom, DesignTokens.Spacing.section)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                    bodySections(host)
                }
                .padding(DesignTokens.Spacing.surface)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Don't offer to scroll something that already fits. The default bounces regardless,
            // which reads as "there is more below" on a panel where there is not.
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
        }
        // No background of its own. This used to carry .ultraThinMaterial on the grounds that "the
        // panel sits over the table" — true when it was an HStack sibling overlapping the content,
        // false now that it is a sheet. A sheet is already its own surface, and a material inside
        // one samples the sheet's own background and renders as dead grey. ContentView gives the
        // sheet its glass through .presentationBackground.
        .onAppear { beginEditing() }
        .onDisappear { commitLabelIfChanged() }
        .onChange(of: host.id) { _, _ in
            // Runs after `host`/`label` have already become the new host's, which is exactly why
            // the commit below must use the captured anchor and snapshot.
            commitLabelIfChanged()
            beginEditing()
        }
    }

    private func beginEditing() {
        labelText = label ?? ""
        labelSnapshot = label
        editingAnchor = anchor
    }

    /// Everything below the header. The header is not in here because it does not scroll.
    @ViewBuilder
    private func bodySections(_ host: Host) -> some View {
        labelSection(host: host)
        Divider()
        infoSection(host: host)
        if !services.isEmpty {
            Divider()
            servicesSection
        }
        Divider()
        PingMonitorView(ip: host.ip)
        Divider()
        actionsSection(host: host)
    }

    /// Done, bottom-trailing, default action — where macOS puts a sheet's way out, and what ⏎ hits.
    ///
    /// This replaces an X in the top-right corner, which is a *panel's* affordance: it meant "hide
    /// this thing that lives here". A sheet is opened for one host and dismissed, so the button says
    /// what it does.
    private var footer: some View {
        HStack {
            Spacer()
            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DesignTokens.Spacing.surface)
        .padding(.vertical, DesignTokens.Spacing.section)
    }


    /// Writes the edit to the host it was typed against.
    ///
    /// This used to call back into a closure that re-read the *current* selection, so typing a
    /// label on host A and clicking host B wrote A's text onto B — and closing the panel dropped
    /// the text entirely, because by then there was no selection to guard against.
    private func commitLabelIfChanged() {
        guard let editingAnchor else { return }
        let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (labelSnapshot ?? "") {
            onLabelChange(editingAnchor, trimmed.isEmpty ? nil : trimmed)
            labelSavedAt = Date()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if let saved = labelSavedAt, Date().timeIntervalSince(saved) >= 1.4 {
                    labelSavedAt = nil
                }
            }
        }
    }

    // MARK: - Sections

    /// Why the scan thinks this host is what it says it is.
    private func classificationReason(_ host: Host) -> String {
        let result = host.classification
        guard !result.matchedRuleIDs.isEmpty else { return result.confidence.label }
        return """
        \(result.confidence.label) — score \(result.score)
        Matched: \(result.matchedRuleIDs.joined(separator: ", "))
        """
    }

    @ViewBuilder
    private func header(host: Host) -> some View {
        let kind = host.deviceType
        HStack(alignment: .top, spacing: 12) {
            AccentTile(size: 48) {
                Image(systemName: kind.sfSymbol)
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.ip).font(.title3).fontWeight(.medium).monospaced()
                    .textSelection(.enabled)
                if let v = host.vendor {
                    Text(v).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if kind != .unknown {
                    // The confidence is shown, not just the verdict. A device the scan is guessing
                    // at and one it is certain of should not look identical — and the tooltip names
                    // the rules that fired, so a wrong answer can be argued with rather than just
                    // disbelieved.
                    HStack(spacing: 4) {
                        Text(kind.label)
                        if host.classification.confidence < .high {
                            Text("· \(host.classification.confidence.label)")
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help(classificationReason(host))
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func labelSection(host: Host) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Label").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if labelSavedAt != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            TextField("Add label…  (e.g. NAS  #server)", text: $labelText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitLabelIfChanged() }
            Text("Press Enter to save · #tag is searchable")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func infoSection(host: Host) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Names off the wire are worth attributing: a Bonjour name is whatever the device
            // chose to call itself, which is not the same claim as a PTR record.
            infoRow("Name", resolvedName.map { name in
                name.source == .dns ? name.value : "\(name.value) (\(name.source.rawValue))"
            })
            if let nb = host.netbiosName {
                infoRow("NetBIOS", nb)
            }
            if let wg = host.workgroup {
                infoRow("Workgroup", wg)
            }
            infoRow("MAC", host.mac?.uppercased(), monospaced: true)
            infoRow("Anchor", anchor, monospaced: true, secondary: true)
            // Shown even with nothing open: "scanned, all closed" is a result worth stating, and
            // hiding the row made it indistinguishable from never having scanned.
            infoRow("Ports", PortScanner.displayList(open: host.openPorts, scanned: host.scannedPorts))
            if let t = host.serviceTitle {
                infoRow("Title", t)
            }
            if let rtt = host.rttMs {
                infoRow("RTT (initial)", String(format: "%.1f ms", rtt), monospaced: true)
            }
            if let ttl = host.ttl {
                infoRow("TTL", String(ttl), monospaced: true)
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ key: String, _ value: String?, monospaced: Bool = false, secondary: Bool = false) -> some View {
        InfoRow(
            key: key,
            value: value,
            font: secondary ? .caption : .callout,
            monospaced: monospaced,
            valueLineLimit: 3
        )
    }

    @ViewBuilder
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Services (mDNS)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(services.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(services, id: \.self) { svc in
                    HStack(spacing: 6) {
                        AccentTile(cornerRadius: DesignTokens.Radius.small) {
                            Text(svc.displayType)
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.horizontal, DesignTokens.Spacing.tight + 2)
                                .padding(.vertical, 1)
                        }
                        Text(svc.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(host: Host) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
            actionGroup("Connect") {
                ActionButton("HTTP", systemImage: "safari") {
                    HostActions.openBrowser(ip: host.ip)
                }
                ActionButton("HTTPS", systemImage: "lock.shield") {
                    HostActions.openBrowser(ip: host.ip, scheme: "https")
                }
                ActionButton("SSH", systemImage: "terminal") {
                    HostActions.openSSH(ip: host.ip)
                }
                ActionButton("VNC", systemImage: "rectangle.connected.to.line.below") {
                    HostActions.openVNC(ip: host.ip)
                }
                ActionButton("RDP", systemImage: "display") {
                    HostActions.openRDP(ip: host.ip)
                }
                ActionButton("SMB", systemImage: "externaldrive.connected.to.line.below") {
                    HostActions.openSMB(ip: host.ip)
                }
                ActionButton("AFP", systemImage: "externaldrive") {
                    HostActions.openAFP(ip: host.ip)
                }
                ActionButton("Telnet", systemImage: "terminal.fill") {
                    HostActions.openTelnet(ip: host.ip)
                }
            }

            actionGroup("Tools") {
                ActionButton("Ping", systemImage: "wave.3.right") {
                    HostActions.pingInTerminal(ip: host.ip)
                }
                if let mac = host.mac {
                    ActionButton("Wake", systemImage: "power.circle.fill") {
                        Task { await HostActions.wakeOnLAN(mac: mac) }
                    }
                }
            }

            actionGroup("Copy") {
                ActionButton("IP", systemImage: "doc.on.doc") {
                    HostActions.copy(host.ip)
                }
                if let hostname = host.hostname {
                    ActionButton("Hostname", systemImage: "doc.on.doc") {
                        HostActions.copy(hostname)
                    }
                }
                if let mac = host.mac {
                    ActionButton("MAC", systemImage: "doc.on.doc") {
                        HostActions.copy(mac.uppercased())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 60), spacing: DesignTokens.Spacing.tight + 2),
                    count: 3
                ),
                spacing: DesignTokens.Spacing.tight + 2
            ) {
                content()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// One button in an `actionGroup` grid.
///
/// Exists for the `.frame(maxWidth: .infinity)`, which has to be on the *label* to do anything. It
/// used to be on the LazyVGrid, under a comment explaining that it made each button fill its cell —
/// which is what it was for, and not what it did: it stretched the grid, and left the buttons inside
/// hugging their own text. So "HTTP" rendered half the width of "Telnet" and the grid read as ragged
/// even though its columns were even, which is precisely the bug the comment claimed to have fixed.
///
/// A type rather than a modifier repeated thirteen times, so the next button added to a group cannot
/// be the one that forgets.
private struct ActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Ping monitor isolated child view

/// Isolated subview that owns the PingMonitor. When samples update every second,
/// only this view re-renders — not the entire HostInspector — preventing AppKit
/// constraint loops in the inspector column.
struct PingMonitorView: View {
    let ip: String
    @State private var monitor = PingMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ping (live)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let rtt = monitor.lastRTT {
                    Text(String(format: "%.1f ms", rtt))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(.green)
                } else if !monitor.samples.isEmpty {
                    Text("no response")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            PingSparkline(samples: monitor.samples)
                .frame(height: 56)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 14) {
                if let avg = monitor.avgRTT {
                    Text("avg \(String(format: "%.1f", avg))")
                        .monospacedDigit()
                }
                if let lo = monitor.minRTT, let hi = monitor.maxRTT {
                    Text("min \(String(format: "%.1f", lo)) · max \(String(format: "%.1f", hi))")
                        .monospacedDigit()
                }
                Spacer()
                Text("loss \(Int(monitor.lossRate * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(monitor.lossRate > 0 ? .red : .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            monitor.start(ip: ip)
        }
        .onDisappear {
            monitor.stop()
        }
        .onChange(of: ip) { _, newIP in
            monitor.start(ip: newIP)
        }
    }
}

struct PingSparkline: View {
    let samples: [Double?]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count >= 2 else { return }
            let alive = samples.compactMap { $0 }
            guard !alive.isEmpty else { return }

            let maxV = alive.max() ?? 1
            let minV = alive.min() ?? 0
            let range = max(maxV - minV, 1)

            let topPad: CGFloat = 4
            let bottomPad: CGFloat = 4
            let h = max(size.height - topPad - bottomPad, 1)
            let w = max(size.width - 8, 1)
            let stepX = w / CGFloat(max(samples.count - 1, 1))

            var path = Path()
            var movedTo = false
            for (i, sample) in samples.enumerated() {
                let x = 4 + CGFloat(i) * stepX
                if let v = sample {
                    let y = topPad + (h - CGFloat(v - minV) / CGFloat(range) * h)
                    if !movedTo {
                        path.move(to: .init(x: x, y: y))
                        movedTo = true
                    } else {
                        path.addLine(to: .init(x: x, y: y))
                    }
                } else {
                    ctx.fill(
                        Path(ellipseIn: .init(x: x - 1.5, y: size.height - 4, width: 3, height: 3)),
                        with: .color(.red)
                    )
                    movedTo = false
                }
            }
            ctx.stroke(path, with: .color(.green), lineWidth: 1.5)
        }
    }
}
