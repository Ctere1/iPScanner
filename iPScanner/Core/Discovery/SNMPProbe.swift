import Foundation

/// Asks a host for its SNMP system description.
enum SNMPProbe {
    /// The community string every device ships with and most never change. Read-only, and only
    /// ever asked for the three system OIDs below.
    static let defaultCommunity = "public"

    static func probe(
        _ ip: String,
        community: String = defaultCommunity,
        timeoutMs: Int = 1000
    ) async -> SNMPResult? {
        // Random per request so a reply cannot be matched to the wrong query if two are in flight
        // to the same host.
        let requestID = Int32.random(in: 1...Int32.max)
        let request = SNMPMessage.get(
            oids: SNMPMessage.defaultOIDs,
            community: community,
            requestID: requestID
        )
        guard let reply = await NWProbe.exchange(
            ip, port: SNMPMessage.port, payload: request, timeoutMs: timeoutMs
        ) else { return nil }
        return SNMPMessage.result(from: reply)
    }
}
