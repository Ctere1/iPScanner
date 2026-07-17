import Foundation
import UniformTypeIdentifiers

/// Saving and copying the host table in each supported format.
///
/// Was ~90 lines of file I/O living directly in ContentView's body scope. The view now names the
/// action; this decides what to encode and where it goes.
@MainActor
struct ExportCoordinator {
    let controller: ScanController

    enum Format: String, CaseIterable, Identifiable {
        case csv
        case json
        case ipPort
        case textReport

        var id: String { rawValue }

        /// Menu wording for the save variant.
        var saveTitle: String {
            switch self {
            case .csv: "Save as CSV…"
            case .json: "Save as JSON…"
            case .ipPort: "Save as IP:Port List…"
            case .textReport: "Save as Text Report…"
            }
        }

        /// Menu wording for the copy variant.
        var copyTitle: String {
            switch self {
            case .csv: "Copy to Clipboard (CSV)"
            case .json: "Copy to Clipboard (JSON)"
            case .ipPort: "Copy to Clipboard (IP:Port)"
            case .textReport: "Copy to Clipboard (Text Report)"
            }
        }

        var contentType: UTType {
            switch self {
            case .csv: .commaSeparatedText
            case .json: .json
            case .ipPort, .textReport: .plainText
            }
        }

        var fileExtension: String {
            switch self {
            case .csv: "csv"
            case .json: "json"
            case .ipPort, .textReport: "txt"
            }
        }
    }

    // MARK: - Actions

    func save(_ format: Format) {
        guard let text = encode(format) else { return }
        do {
            try FilePanels.save(
                Data(text.utf8),
                contentType: format.contentType,
                defaultName: ExportService.defaultFileName(ext: format.fileExtension)
            )
        } catch {
            controller.report(
                title: "Save failed",
                message: "Could not write the file.\n\n\(error.localizedDescription)"
            )
        }
    }

    func copy(_ format: Format) {
        guard let text = encode(format) else { return }
        HostActions.copy(text)
    }

    /// The selected IPs, one per line.
    ///
    /// filteredHosts, not hosts: copy what is selected *and* visible, which is what the user
    /// believes they picked.
    func copySelectedIPs() {
        let ips = controller.filteredHosts
            .filter { controller.selection.contains($0.id) }
            .map(\.ip)
        guard !ips.isEmpty else { return }
        HostActions.copy(ips.joined(separator: "\n"))
    }

    // MARK: - Encoding

    private func rows() -> [ExportService.Row] {
        ExportService.rows(from: controller.filteredHosts) { controller.label(for: $0) }
    }

    /// nil means encoding failed and the user has already been told.
    private func encode(_ format: Format) -> String? {
        switch format {
        case .csv:
            return ExportService.csv(rows: rows())
        case .ipPort:
            return ExportService.ipPortList(rows: rows())
        case .textReport:
            return textReport()
        case .json:
            do {
                let data = try ExportService.json(rows: rows())
                return String(data: data, encoding: .utf8)
            } catch {
                controller.report(
                    title: "Export failed",
                    message: "Could not encode JSON.\n\n\(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    private func textReport() -> String {
        let rangeLabel: String
        if let imported = controller.importedTargets {
            rangeLabel = "Imported list: \(imported.url.lastPathComponent) (\(imported.targets.count) targets)"
        } else {
            rangeLabel = controller.rangeInput
        }
        // The scan's declared total, not the row count: a report of a filtered table should still
        // say how many addresses were actually looked at.
        let scannedTotal: Int
        switch controller.state {
        case .scanning(_, let total), .done(_, let total): scannedTotal = total
        case .idle: scannedTotal = controller.hosts.count
        }
        return ExportService.textReport(
            rows: rows(),
            rangeInput: rangeLabel,
            scannedTotal: scannedTotal,
            aliveCount: controller.aliveCount
        )
    }
}
