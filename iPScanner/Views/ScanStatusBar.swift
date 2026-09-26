import SwiftUI

extension ContentView {
    var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                switch controller.state {
                case .idle:
                    Text("Ready").foregroundStyle(.secondary)
                case .scanning(let scanned, let total):
                    ProgressView().controlSize(.small)
                    Text(controller.phase.rawValue)
                    if controller.portScanInProgress {
                        Text("\(controller.portScanProgress.scanned)/\(controller.portScanProgress.total)")
                    } else {
                        Text("\(scanned)/\(total)")
                    }
                case .stopped(let scanned, let total):
                    Text("Stopped: \(scanned) of \(total)").foregroundStyle(.secondary)
                case .done(let scanned, let total):
                    Text("Completed: \(scanned) of \(total)")
                }
                Spacer()
                if controller.elapsed > 0 {
                    Text(String(format: "%.1fs", controller.elapsed)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if !controller.hosts.isEmpty {
                HStack(spacing: 8) {
                    Text("\(controller.aliveCount) alive").foregroundStyle(.green)
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

                }
            }
            if let error = controller.lastError, !controller.hosts.isEmpty {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
