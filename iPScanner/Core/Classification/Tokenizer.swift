import Foundation

/// Splits a hostname into the words it is actually made of.
///
/// The classifier used to ask `hostname.contains("tv")`, which is true of `natview`, and
/// `hostname.contains("nas")`, which is true of `jonas-pc`. Substring matching on a hostname cannot
/// be made safe by picking better substrings — the fix is to stop doing it and compare whole
/// tokens.
enum Tokenizer {
    /// Lowercases, drops the DNS domain, and splits on punctuation *and* on digit↔letter
    /// boundaries.
    ///
    ///     "Jonas-PC.local"     → ["jonas", "pc"]
    ///     "natview"            → ["natview"]          — no "tv" token
    ///     "HP-LaserJet-M404dn" → ["hp", "laserjet", "m", "404", "dn"]
    ///     "Cemils-iPhone"      → ["cemils", "iphone"]
    ///
    /// The digit↔letter split is what makes model numbers usable: without it `m404dn` is one opaque
    /// token that no rule can match.
    static func tokens(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty else { return [] }

        // Only the leftmost label: "printer.office.example.com" is a printer, and the domain would
        // otherwise contribute tokens belonging to the network rather than the device.
        let host = raw.lowercased().split(separator: ".").first.map(String.init) ?? raw.lowercased()

        var tokens: Set<String> = []
        var current = ""
        var lastWasDigit: Bool?

        func flush() {
            if !current.isEmpty { tokens.insert(current) }
            current = ""
        }

        for char in host {
            guard char.isLetter || char.isNumber else {
                flush()
                lastWasDigit = nil
                continue
            }
            let isDigit = char.isNumber
            if let last = lastWasDigit, last != isDigit {
                flush()
            }
            current.append(char)
            lastWasDigit = isDigit
        }
        flush()
        return tokens
    }
}
