import AppKit
import UniformTypeIdentifiers

/// The open/save panels, in one place.
///
/// Three copies of the same NSOpenPanel setup lived in ContentView, differing only in their content
/// types and prompt.
@MainActor
enum FilePanels {
    /// Runs an open panel and returns the chosen file, or nil if the user cancelled.
    static func open(
        contentTypes: [UTType],
        message: String? = nil,
        prompt: String? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let message { panel.message = message }
        if let prompt { panel.prompt = prompt }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Runs a save panel and writes `data`.
    ///
    /// Throws rather than swallowing: a silent `try?` made a read-only volume, a sandbox denial or
    /// a full disk look exactly like a successful save.
    ///
    /// - Returns: the file written, or nil if the user cancelled.
    @discardableResult
    static func save(_ data: Data, contentType: UTType, defaultName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url)
        return url
    }
}
