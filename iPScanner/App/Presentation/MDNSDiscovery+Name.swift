import Foundation

extension MDNSDiscovery {
    /// Reverse DNS first, then the names the scan picked up elsewhere.
    ///
    /// Lives on the discovery rather than the view: it is the only party that holds the Bonjour
    /// half, and both the table and the inspector need the answer.
    func resolvedName(for host: Host) -> ResolvedName? {
        ResolvedName.best(
            dns: host.hostname,
            mdns: name(for: host.ip),
            netbios: host.netbiosName
        )
    }
}
