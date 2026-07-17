import Foundation
import Network

/// Asks one host what it advertises over UPnP, and optionally reads its description document.
enum SSDPProbe {
    /// A description document should be a few KB. The cap is there because the URL comes from the
    /// device being scanned, which is to say from an untrusted party on the network.
    static let maxDescriptionBytes = 256 * 1024
    static let descriptionTimeout: TimeInterval = 1.5

    /// Unicast M-SEARCH to `ip`. See SSDPResponse.searchRequest for why unicast.
    static func probe(_ ip: String, timeoutMs: Int = 1200) async -> SSDPResult? {
        let request = SSDPResponse.searchRequest(host: ip)
        guard let reply = await NWProbe.exchange(
            ip, port: SSDPResponse.port, payload: request, timeoutMs: timeoutMs
        ) else { return nil }
        return SSDPResponse.parse(reply)
    }

    /// Fetches and parses the description document a probe pointed at.
    static func describe(_ location: URL) async -> UPnPDescription? {
        // Only ever an http URL on the local network, and only one the device itself named.
        guard let scheme = location.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        var request = URLRequest(url: location)
        request.timeoutInterval = descriptionTimeout
        request.httpMethod = "GET"

        guard let (data, response) = try? await BannerProbe.permissiveSession.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty
        else { return nil }

        return UPnPDescription.parse(data.prefix(maxDescriptionBytes))
    }

    /// Probe, then follow the LOCATION header if there is one.
    static func probeAndDescribe(_ ip: String, timeoutMs: Int = 1200) async -> (SSDPResult, UPnPDescription?)? {
        guard let result = await probe(ip, timeoutMs: timeoutMs) else { return nil }
        guard let location = result.location else { return (result, nil) }
        return (result, await describe(location))
    }
}
