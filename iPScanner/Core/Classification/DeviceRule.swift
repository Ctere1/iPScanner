import Foundation

/// One test against a host's signals.
indirect enum Matcher: Sendable {
    case port(Int)
    case anyPort([Int])

    case mdns(String)
    case anyMDNS([String])
    /// A TXT key whose value starts with `hasPrefix`, compared case-insensitively.
    case mdnsTXT(key: String, hasPrefix: String)

    /// Substring of the pooled vendor/title/NetBIOS text. Safe there: it is prose, not an
    /// identifier — unlike a hostname, where substrings produce `natview` → "tv".
    case descrPhrase(String)
    case anyDescrPhrase([String])

    /// Whole-token match against the hostname. Never a substring.
    case hostToken(String)
    case anyHostToken([String])

    /// Observed TTL is `initial - hops`, so this matches a window below the initial value rather
    /// than an exact number. 64 (Linux/Apple), 128 (Windows) and 255 (network gear) are far enough
    /// apart that the windows do not overlap.
    case ttlNear(Int, tolerance: Int = 8)

    case isGateway
    case hasWorkgroup

    case not(Matcher)
    case all([Matcher])
    case any([Matcher])

    func matches(_ s: DeviceSignals) -> Bool {
        switch self {
        case .port(let p):
            return s.openPorts.contains(p)
        case .anyPort(let ports):
            return ports.contains { s.openPorts.contains($0) }

        case .mdns(let type):
            return s.mdnsTypes.contains(type)
        case .anyMDNS(let types):
            return types.contains { s.mdnsTypes.contains($0) }
        case .mdnsTXT(let key, let prefix):
            guard let value = s.mdnsTXT[key.lowercased()] else { return false }
            return value.lowercased().hasPrefix(prefix.lowercased())

        case .descrPhrase(let phrase):
            return s.descriptionText.contains(phrase.lowercased())
        case .anyDescrPhrase(let phrases):
            return phrases.contains { s.descriptionText.contains($0.lowercased()) }

        case .hostToken(let token):
            return s.hostnameTokens.contains(token)
        case .anyHostToken(let tokens):
            return tokens.contains { s.hostnameTokens.contains($0) }

        case .ttlNear(let value, let tolerance):
            guard let ttl = s.ttl else { return false }
            return ttl <= value && ttl > value - tolerance

        case .isGateway:
            return s.isDefaultGateway
        case .hasWorkgroup:
            return s.workgroup?.isEmpty == false

        case .not(let inner):
            return !inner.matches(s)
        case .all(let inner):
            return inner.allSatisfy { $0.matches(s) }
        case .any(let inner):
            return inner.contains { $0.matches(s) }
        }
    }
}

/// A weighted piece of evidence for one device type.
struct DeviceRule: Sendable {
    /// Stable and addressable, e.g. `printer.port.raw9100`. Tests assert on these, and the
    /// inspector shows them as the reason for a verdict.
    let id: String
    let type: DeviceType
    let weight: Int
    let matcher: Matcher

    init(_ id: String, _ type: DeviceType, _ weight: Int, _ matcher: Matcher) {
        self.id = id
        self.type = type
        self.weight = weight
        self.matcher = matcher
    }
}

/// The weights, named. Ad-hoc numbers scattered through a rule table stop meaning anything within a
/// week; these are the only values rules should use.
enum W {
    /// Enough on its own, and enough to beat anything short of another decisive signal.
    /// `model=iPhone15,2`. Port 9100. `_googlecast._tcp`.
    static let decisive = 6
    /// A single-purpose manufacturer, or a port only one kind of thing opens.
    static let strong = 4
    /// Needs no corroboration but is beatable.
    static let moderate = 3
    /// Corroborating only — TTL 128 says "Windows-ish", not "Windows".
    static let weak = 2
    /// Tie-break dust.
    static let hint = 1
    /// Actively argues against a type.
    static let penalty = -4
}
