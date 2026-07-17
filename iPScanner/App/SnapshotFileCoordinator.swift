import Foundation
import UniformTypeIdentifiers

/// Reading and writing `.ipscan.json` scan files.
///
/// Was three near-identical panel-plus-decode blocks in ContentView's body scope.
@MainActor
struct SnapshotFileCoordinator {
    let controller: ScanController

    func save() {
        let data: Data
        do {
            data = try SnapshotIO.encode(controller.makeSnapshot())
        } catch {
            controller.report(
                title: "Save failed",
                message: "Could not encode the scan file.\n\n\(error.localizedDescription)"
            )
            return
        }
        do {
            try FilePanels.save(data, contentType: .json, defaultName: SnapshotIO.defaultFileName())
        } catch {
            controller.report(
                title: "Save failed",
                message: "Could not write the scan file.\n\n\(error.localizedDescription)"
            )
        }
    }

    /// Replaces the current results with a saved scan.
    func open() {
        guard let snapshot = read(message: nil, failureTitle: "Could not open scan file") else { return }
        controller.applySnapshot(snapshot)
    }

    /// Loads a scan to diff the current results against.
    func openComparisonBaseline() {
        guard let snapshot = read(
            message: "Pick a previous scan to compare against the current results.",
            failureTitle: "Could not open baseline"
        ) else { return }
        controller.loadComparisonBaseline(snapshot)
    }

    private func read(message: String?, failureTitle: String) -> ScanSnapshot? {
        guard let url = FilePanels.open(contentTypes: [.json], message: message) else { return nil }
        do {
            return try SnapshotIO.decode(try Data(contentsOf: url))
        } catch {
            controller.report(title: failureTitle, message: error.localizedDescription)
            return nil
        }
    }
}
