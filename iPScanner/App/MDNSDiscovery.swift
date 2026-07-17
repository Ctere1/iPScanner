import Foundation
import Network
import Observation

@Observable
@MainActor
final class MDNSDiscovery {
    struct ServiceRecord: Hashable {
        let displayType: String
        let serviceType: String
        let name: String
        let ip: String
        /// The service's TXT record, keys lowercased.
        ///
        /// `_device-info._tcp` puts the hardware identifier here — `model=MacBookPro18,3`,
        /// `model=iPhone15,2`, `model=AudioAccessory5,1` — which is the single most precise
        /// statement a device on a LAN makes about what it is. It arrives with the browse result
        /// at no extra cost, and used to be thrown away.
        var txt: [String: String] = [:]
    }

    static let serviceTypes: [(type: String, label: String)] = [
        ("_airplay._tcp", "AirPlay"),
        ("_raop._tcp", "AirPlay Audio"),
        ("_googlecast._tcp", "Chromecast"),
        ("_companion-link._tcp", "Apple Companion"),
        ("_homekit._tcp", "HomeKit"),
        ("_hap._tcp", "HomeKit"),
        ("_smb._tcp", "SMB"),
        ("_afpovertcp._tcp", "AFP"),
        ("_nfs._tcp", "NFS"),
        ("_ssh._tcp", "SSH"),
        ("_rfb._tcp", "VNC"),
        ("_workstation._tcp", "Workstation"),
        ("_http._tcp", "HTTP"),
        ("_https._tcp", "HTTPS"),
        ("_ipp._tcp", "IPP"),
        ("_printer._tcp", "Printer"),
        ("_pdl-datastream._tcp", "Print"),
        ("_device-info._tcp", "Device Info")
    ]

    static let resolveTimeoutMs = 3000

    private(set) var servicesByIP: [String: Set<ServiceRecord>] = [:]
    private var browsers: [NWBrowser] = []
    private var pendingConnections: [NWConnection] = []
    /// Endpoints already resolved or currently being resolved. `browseResultsChangedHandler`
    /// hands back the whole result set on every change, so without this each new device on the
    /// network re-resolved every service already known — a connection storm that grew with the
    /// square of the number of services, for the app's whole lifetime.
    private var seenEndpoints: Set<EndpointKey> = []
    private let resolveQueue = DispatchQueue(
        label: "iPScanner.mdns.resolve",
        attributes: .concurrent
    )

    private struct EndpointKey: Hashable {
        let name: String
        let type: String
        let domain: String
    }

    var isRunning: Bool { !browsers.isEmpty }

    func start() {
        guard browsers.isEmpty else { return }
        for (type, label) in Self.serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: "local.")
            let browser = NWBrowser(for: descriptor, using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    self?.handle(results: results, displayType: label)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        for b in browsers { b.cancel() }
        browsers.removeAll()
        for c in pendingConnections { c.cancel() }
        pendingConnections.removeAll()
        seenEndpoints.removeAll()
    }

    func services(for ip: String) -> [ServiceRecord] {
        Array(servicesByIP[ip] ?? []).sorted {
            if $0.displayType == $1.displayType { return $0.name < $1.name }
            return $0.displayType < $1.displayType
        }
    }

    func uniqueServiceTypes(for ip: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for s in services(for: ip) where !seen.contains(s.displayType) {
            seen.insert(s.displayType)
            ordered.append(s.displayType)
        }
        return ordered
    }

    // MARK: - Internals

    private func handle(results: Set<NWBrowser.Result>, displayType: String) {
        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            let key = EndpointKey(name: name, type: type, domain: domain)
            guard seenEndpoints.insert(key).inserted else { continue }
            resolveService(
                name: name,
                type: type,
                domain: domain,
                displayType: displayType,
                txt: Self.txtDictionary(result.metadata)
            )
        }
    }

    /// Bonjour hands the TXT record over with the browse result — resolving it costs nothing extra.
    static func txtDictionary(_ metadata: NWBrowser.Result.Metadata) -> [String: String] {
        guard case .bonjour(let record) = metadata else { return [:] }
        var out: [String: String] = [:]
        for (key, entry) in record {
            if case .string(let value) = entry {
                out[key.lowercased()] = value
            }
        }
        return out
    }

    private func resolveService(
        name: String,
        type: String,
        domain: String,
        displayType: String,
        txt: [String: String]
    ) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        pendingConnections.append(connection)
        let key = EndpointKey(name: name, type: type, domain: domain)

        // Without a timeout a connection to an advertised-but-unreachable service sits in
        // `.waiting` forever: it never reaches a terminal state, so the handler below never runs,
        // and the connection — which owns the handler that captures it — leaks along with its
        // entry in `pendingConnections`.
        let timeoutWork = DispatchWorkItem { connection.cancel() }
        resolveQueue.asyncAfter(deadline: .now() + .milliseconds(Self.resolveTimeoutMs), execute: timeoutWork)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                timeoutWork.cancel()
                let resolved: String? = {
                    guard let path = connection.currentPath,
                          case .hostPort(let host, _) = path.remoteEndpoint else { return nil }
                    return Self.ipv4String(from: host)
                }()
                connection.cancel()
                Task { @MainActor in
                    if let ip = resolved {
                        self?.add(
                            record: ServiceRecord(
                                displayType: displayType,
                                serviceType: type,
                                name: name,
                                ip: ip,
                                txt: txt
                            )
                        )
                    } else {
                        // Nothing learned, so allow a later browse callback to retry this endpoint.
                        self?.seenEndpoints.remove(key)
                    }
                    self?.dropConnection(connection)
                }
            case .failed, .cancelled:
                timeoutWork.cancel()
                Task { @MainActor in
                    self?.seenEndpoints.remove(key)
                    self?.dropConnection(connection)
                }
            default:
                break
            }
        }
        connection.start(queue: resolveQueue)
    }

    /// Bonjour service types advertised by `ip`, e.g. `_ipp._tcp`.
    func serviceTypes(for ip: String) -> Set<String> {
        Set(services(for: ip).map(\.serviceType))
    }

    /// TXT records for `ip`, merged across its services.
    ///
    /// `_device-info._tcp` carries `model=`, which names Apple hardware exactly — the reason the
    /// TXT record is captured at all.
    func txt(for ip: String) -> [String: String] {
        var merged: [String: String] = [:]
        for record in services(for: ip) {
            merged.merge(record.txt) { existing, _ in existing }
        }
        return merged
    }

    /// Best human-readable name Bonjour knows for `ip`, if any. Service instance names are what
    /// the device chose to call itself ("Cemil MacBook Pro"), which is exactly what a scan wants
    /// to show when reverse DNS has no PTR record.
    func name(for ip: String) -> String? {
        let records = services(for: ip)
        guard !records.isEmpty else { return nil }
        // Prefer the type most likely to carry the device's own name over a per-service label.
        let preferred = ["_device-info._tcp", "_workstation._tcp", "_companion-link._tcp", "_smb._tcp"]
        for type in preferred {
            if let match = records.first(where: { $0.serviceType == type }) {
                return Self.cleanName(match.name)
            }
        }
        return Self.cleanName(records[0].name)
    }

    /// `_workstation._tcp` instances are advertised as "name [00:11:22:33:44:55]"; drop the suffix.
    private static func cleanName(_ raw: String) -> String {
        guard let bracket = raw.firstIndex(of: "[") else { return raw }
        let trimmed = raw[..<bracket].trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? raw : trimmed
    }

    private func add(record: ServiceRecord) {
        servicesByIP[record.ip, default: []].insert(record)
    }

    private func dropConnection(_ connection: NWConnection) {
        pendingConnections.removeAll { $0 === connection }
    }

    nonisolated private static func ipv4String(from host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let addr):
            let bytes = addr.rawValue
            guard bytes.count == 4 else { return nil }
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        default:
            return nil
        }
    }
}
