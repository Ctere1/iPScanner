import Foundation

/// What a UPnP device says about itself in an M-SEARCH reply.
struct SSDPResult: Hashable, Sendable {
    /// The SERVER header — an OS/product string, e.g. "Linux/3.4 UPnP/1.0 Sonos/70.3".
    var server: String?
    /// ST (in a reply) or NT (in a NOTIFY): what kind of thing this is, e.g.
    /// `urn:schemas-upnp-org:device:InternetGatewayDevice:1`.
    var searchTarget: String?
    /// Where the full device description XML lives.
    var location: URL?
    var usn: String?

    var isEmpty: Bool {
        server == nil && searchTarget == nil && location == nil && usn == nil
    }
}

/// Parses SSDP's HTTP-shaped datagrams.
///
/// Pure, and the reason the probe is worth having: the wire format is fixed, so every interesting
/// case — a real Sonos reply, an IGD, a NOTIFY, a truncated packet — is a byte array in a test
/// rather than a device someone has to own.
enum SSDPResponse {
    static let port: UInt16 = 1900

    /// A unicast M-SEARCH.
    ///
    /// Sent to the host directly rather than multicast to 239.255.255.250. Multicast on Apple
    /// platforms needs the `com.apple.developer.networking.multicast` entitlement, which Apple
    /// grants by request and this app does not have — and for a subnet scan it would buy nothing,
    /// since the only devices it reaches that unicast does not are ones outside the range being
    /// scanned. Unicast also fits the existing bounded per-host pipeline instead of being an
    /// unbounded broadcast.
    static func searchRequest(host: String, searchTarget: String = "ssdp:all", mx: Int = 1) -> Data {
        let request = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(host):\(port)",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(searchTarget)",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(request.utf8)
    }

    /// Parses a 200 OK reply or a NOTIFY. Returns nil when the datagram carries nothing useful.
    static func parse(_ data: Data) -> SSDPResult? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              !text.isEmpty else { return nil }

        var headers: [String: String] = [:]
        // `isNewline`, not a comparison against "\r" and "\n": Swift treats CRLF as a *single*
        // Character, which equals neither of them — so the obvious-looking predicate splits an
        // actual SSDP datagram into exactly one line and finds no headers at all. This also gets
        // the tolerance for free: the RFC says CRLF and devices send bare LF.
        let lines = text.split(whereSeparator: \.isNewline)
        guard let statusLine = lines.first else { return nil }

        // Either an HTTP reply or a NOTIFY announcement; anything else is not ours.
        let status = statusLine.uppercased()
        guard status.contains("HTTP/1.1") || status.hasPrefix("NOTIFY") else { return nil }

        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmed.uppercased()
            let value = String(line[line.index(after: colon)...]).trimmed
            guard !name.isEmpty, !value.isEmpty else { continue }
            // First wins: a duplicate header is malformed, and the first is what a reader would
            // most likely have taken.
            if headers[name] == nil { headers[name] = value }
        }

        var result = SSDPResult()
        result.server = headers["SERVER"]
        // ST in a reply, NT in a NOTIFY — the same fact under two names.
        result.searchTarget = headers["ST"] ?? headers["NT"]
        result.usn = headers["USN"]
        result.location = headers["LOCATION"].flatMap { URL(string: $0) }

        return result.isEmpty ? nil : result
    }
}
