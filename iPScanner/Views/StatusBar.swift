import SwiftUI

/// Split out of `ContentView` deliberately: it reads `controller.elapsed`, which ticks while a scan
/// runs. As a computed property of ContentView that read made every tick invalidate the whole body,
/// re-filtering and re-sorting the entire host table. As its own View, only this bar redraws.
struct StatusBar: View {
    let controller: ScanController
    @State private var showingWarnings = false
    @State private var showingDiff = false

    // MARK: - Warnings popover

    @ViewBuilder
    private var warningsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan warnings")
                .font(.headline)
            ForEach(Array(controller.warnings.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(w.label)
                            .fontWeight(.medium)
                    }
                    Text(w.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    // MARK: - Diff popover

    @ViewBuilder
    private func diffPopover(_ diff: SnapshotDiff) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Comparison")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    controller.clearComparison()
                    showingDiff = false
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Text("Baseline: \(diff.baselineCreatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Label("\(diff.newCount) new", systemImage: HostChange.Kind.new.sfSymbol)
                    .foregroundStyle(HostChange.Kind.new.tint)
                Label("\(diff.modifiedCount) changed", systemImage: HostChange.Kind.modified.sfSymbol)
                    .foregroundStyle(HostChange.Kind.modified.tint)
                Label("\(diff.missingCount) missing", systemImage: HostChange.Kind.missing.sfSymbol)
                    .foregroundStyle(HostChange.Kind.missing.tint)
            }
            .font(.callout)

            if !diff.missingRecords.isEmpty {
                Divider()
                Text("Missing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(diff.missingRecords, id: \.ip) { rec in
                            HStack(spacing: 6) {
                                Text(rec.ip).monospaced()
                                if let host = rec.hostname {
                                    Text(host).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let vendor = rec.vendor {
                                    Text(vendor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    var body: some View {
        HStack(spacing: 16) {
            switch controller.state {
            case .idle:
                Text("Ready")
                    .foregroundStyle(.secondary)
            case .scanning(let scanned, let total, let phase):
                // Named, because a scan is four passes and only the first knows the address count.
                // Reporting the first alone showed "254 of 254" and then went quiet for the rest —
                // and the fingerprint pass is the longest of them.
                Text("\(phase.label) \(scanned) of \(total)")
                    .monospacedDigit()
                Text("•").foregroundStyle(.secondary)
                Text("\(controller.aliveCount) alive").foregroundStyle(.green)
            case .done(let scanned, let total):
                Text("Completed: \(scanned) of \(total)")
                Text("•").foregroundStyle(.secondary)
                Text("\(controller.aliveCount) alive").foregroundStyle(.green)
            }
            if !controller.searchQuery.isEmpty && !controller.hosts.isEmpty {
                Text("•").foregroundStyle(.secondary)
                Text("\(controller.filteredHosts.count) of \(controller.hosts.count) match")
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }
            if !controller.warnings.isEmpty {
                Text("•").foregroundStyle(.secondary)
                Button {
                    showingWarnings.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(controller.warnings.count) warning\(controller.warnings.count == 1 ? "" : "s")")
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingWarnings, arrowEdge: .top) {
                    warningsPopover
                }
            }
            if let diff = controller.diff {
                Text("•").foregroundStyle(.secondary)
                Button {
                    showingDiff.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("+\(diff.newCount) ~\(diff.modifiedCount) -\(diff.missingCount)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Comparison vs scan from \(diff.baselineCreatedAt.formatted(date: .abbreviated, time: .shortened))")
                .popover(isPresented: $showingDiff, arrowEdge: .top) {
                    diffPopover(diff)
                }
            }
            Spacer()
            if controller.elapsed > 0 {
                let elapsedFormatted = String(format: "%.1f", controller.elapsed)
                Text("\(elapsedFormatted)s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, DesignTokens.Spacing.section)
        .padding(.vertical, DesignTokens.Spacing.tight + 2)
        // `.bar` was `.headerView` by another name. Naming it makes it the same decision as the
        // toolbar at the other end of the window, rather than two that happen to agree.
        .glass(.statusBar)
    }
}
