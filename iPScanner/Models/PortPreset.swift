import Foundation

/// The canned port lists offered in the port-scan sheet.
///
/// Each preset's list used to be written three times — once as a picker tag, once in the binding's
/// getter to recognise it, and once in its setter to apply it — as bare strings that had to match
/// each other exactly for the picker to reflect what the field held. Adding a preset is now one
/// case.
enum PortPreset: String, CaseIterable, Identifiable {
    case common
    case web
    case remote
    case range
    /// Anything the user typed that is not one of the above. Has no list of its own.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common: "Common"
        case .web: "Web"
        case .remote: "Remote"
        case .range: "1-1024"
        case .custom: "Custom"
        }
    }

    /// The ports this preset fills in, or nil for `.custom`, which describes the field rather than
    /// setting it.
    var portsInput: String? {
        switch self {
        case .common: PortScanner.defaultPortsInput
        case .web: "80, 443, 8080, 8443"
        case .remote: "22, 3389, 5900"
        case .range: "1-1024"
        case .custom: nil
        }
    }

    /// Which preset — if any — a typed port list corresponds to.
    static func matching(_ input: String) -> PortPreset {
        allCases.first { $0.portsInput == input } ?? .custom
    }
}
