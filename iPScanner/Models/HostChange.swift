import Foundation

enum HostChange: Equatable, Sendable {
    case new
    case modified(fields: [ChangedField])
    case missing(record: ScanSnapshot.HostRecord)

    enum ChangedField: String, Sendable, Equatable {
        case hostname
        case mac
        case vendor
        case openPorts
        case serviceTitle
    }

    /// The case without its payload.
    ///
    /// Presentation depends only on which kind of change this is, never on the fields that changed
    /// or the record that went missing. Without this, a summary view that wants the "missing" icon
    /// has to fabricate a `HostRecord` to get at it — which is why StatusBar hardcoded its own
    /// copies of these symbols instead of reading them from here.
    enum Kind: String, CaseIterable, Sendable {
        case new
        case modified
        case missing

        var sfSymbol: String {
            switch self {
            case .new: "plus.circle.fill"
            case .modified: "circle.lefthalf.filled"
            case .missing: "minus.circle.fill"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .new: .new
        case .modified: .modified
        case .missing: .missing
        }
    }

    var sfSymbol: String { kind.sfSymbol }

    var label: String {
        switch self {
        case .new: "New"
        case .modified(let fields): "Changed: " + fields.map(\.rawValue).joined(separator: ", ")
        case .missing: "Missing"
        }
    }
}
