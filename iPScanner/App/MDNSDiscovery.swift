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
        /// The service's own TXT record, keys lowercased, as handed over with the browse result.
        ///
        /// This is per-service metadata — an AirPlay feature bitmask, a printer's queue name. The
        /// hardware identifier does *not* arrive here; see `deviceInfoType`.
        var txt: [String: String] = [:]
    }

    /// `_device-info._tcp` is queried, never browsed — and that distinction is the whole fix.
    ///
    /// It is not a browsable service. Apple devices publish a TXT record at
    /// `<name>._device-info._tcp.local` carrying `model=Mac17,2` / `model=iPhone15,2` /
    /// `model=AudioAccessory5,1`, but they answer no PTR query for the type, so browsing for it
    /// returns nothing, forever, on a network full of Macs.
    ///
    /// It was in the browse list, under a comment claiming the TXT "arrives with the browse result
    /// at no extra cost". It does not arrive at all. Six decisive rules depended on it —
    /// apple.model.iphone, .ipad, .watch, .appletv, .homepod and .mac — so the single most precise
    /// statement a device makes about itself never reached the classifier, and every Apple device
    /// fell back to guesswork: a hostname that happens to contain "macbook", or an OUI vendor lookup
    /// that a private Wi-Fi address defeats. Macs with neither came out as "—".
    ///
    /// Measured rather than reasoned:
    ///   dns-sd -B _device-info._tcp local              → nothing
    ///   dns-sd -Q 'Name._device-info._tcp.local' TXT   → model=Mac17,2
    ///
    /// It must stay in NSBonjourServices: the query needs the same local-network permission the
    /// browse did.
    static let deviceInfoType = "_device-info._tcp"

    /// The Bonjour services browsed, and what to call each one in the inspector.
    ///
    /// Three rules govern this list, and all three have been broken:
    ///
    /// 1. Every type a classification rule names must appear here, or the rule is decorative — the
    ///    browser never looks, so the evidence never arrives. Thirteen rules were dead this way.
    /// 2. Every type here must appear in `NSBonjourServices` in project.yml, or macOS refuses the
    ///    browse and it fails silently.
    /// 3. Every type here must actually *answer* a browse. `_device-info._tcp` does not, and sat
    ///    here regardless — see `deviceInfoType`.
    ///
    /// `BonjourServiceTypeTests` enforces what it can, because none of these failures announce
    /// themselves. Note what it still cannot: a rule matching on `.mdnsTXT` names no service type,
    /// so no test could tell that the TXT behind all six apple.model.* rules never arrived.
    ///
    /// Names are from the registry at dns-sd.org/servicetypes.html.
    static let serviceTypes: [(type: String, label: String)] = [
        // Apple
        ("_airplay._tcp", "AirPlay"),
        ("_raop._tcp", "AirPlay Audio"),
        ("_appletv._tcp", "Apple TV"),
        ("_companion-link._tcp", "Apple Companion"),
        ("_net-assistant._tcp", "Apple Remote Desktop"),
        ("_odisk._tcp", "Optical Disk Sharing"),
        ("_daap._tcp", "iTunes Library"),
        ("_workstation._tcp", "Workstation"),
        // Cast
        ("_googlecast._tcp", "Chromecast"),
        ("_spotify-connect._tcp", "Spotify Connect"),
        ("_sonos._tcp", "Sonos"),
        ("_ipspeaker._tcp", "IP Speaker"),
        // Home automation
        ("_homekit._tcp", "HomeKit"),
        ("_hap._tcp", "HomeKit"),
        ("_matter._tcp", "Matter"),
        ("_matterc._udp", "Matter Commissioning"),
        ("_hue._tcp", "Philips Hue"),
        ("_ep._tcp", "Home Automation"),
        ("_homeauto._tcp", "Home Automation"),
        // Storage
        ("_smb._tcp", "SMB"),
        ("_afpovertcp._tcp", "AFP"),
        ("_nfs._tcp", "NFS"),
        ("_adisk._tcp", "Time Machine"),
        ("_dsm._tcp", "Synology DSM"),
        ("_synology._tcp", "Synology"),
        ("_qnap._tcp", "QNAP"),
        // Printing
        ("_ipp._tcp", "IPP"),
        ("_ipps._tcp", "IPP (TLS)"),
        ("_printer._tcp", "Printer"),
        ("_pdl-datastream._tcp", "Print"),
        ("_scanner._tcp", "Scanner"),
        // Cameras
        ("_rtsp._tcp", "RTSP"),
        ("_onvif._tcp", "ONVIF"),
        ("_axis-video._tcp", "Axis Video"),
        ("_amba-cam._tcp", "Ambarella Camera"),
        ("_cctv._tcp", "CCTV"),
        // Remote access / generic
        ("_ssh._tcp", "SSH"),
        ("_rfb._tcp", "VNC"),
        ("_rdp._tcp", "RDP"),
        ("_http._tcp", "HTTP"),
        ("_https._tcp", "HTTPS")
    ]

    static let resolveTimeoutMs = 3000

    private(set) var servicesByIP: [String: Set<ServiceRecord>] = [:]
    /// `_device-info._tcp` TXT per IP — the `model=` that names Apple hardware exactly.
    ///
    /// Separate from `servicesByIP` because it is not a service anyone advertises: it arrives from a
    /// direct TXT query, keyed by an instance name some *other* service told us about.
    private(set) var deviceInfoByIP: [String: [String: String]] = [:]
    private var browsers: [NWBrowser] = []
    private var pendingConnections: [NWConnection] = []
    /// Instance names already queried for device-info, mapped to the IP that owns them. Doubles as
    /// the dedupe set: every service a Mac publishes carries the same instance name, so without this
    /// a host with six services would fire six identical TXT queries.
    @ObservationIgnored
    private var deviceInfoIPs: [String: String] = [:]
    @ObservationIgnored
    private var deviceInfoQueries: [String: NetService] = [:]
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

    /// `NetService.delegate` is weak, so this has to be owned here or the query goes silent the
    /// instant it is set up.
    ///
    /// `@ObservationIgnored` because it is plumbing, not state: @Observable would otherwise try to
    /// generate an init accessor for a lazy property and fail to compile.
    @ObservationIgnored
    private lazy var deviceInfoDelegate = DeviceInfoDelegate { [weak self] name, txt in
        self?.receiveDeviceInfo(name: name, txt: txt)
    }

    /// Receives `_device-info._tcp` TXT records.
    ///
    /// `startMonitoring()` rather than `resolve()`: resolve waits for an SRV record, and
    /// `_device-info._tcp` has none — there is no port to connect to, the TXT *is* the whole
    /// service. Monitoring issues the bare TXT query, which is the one thing that works.
    private final class DeviceInfoDelegate: NSObject, NetServiceDelegate {
        private let onTXT: @MainActor (String, [String: String]) -> Void

        init(onTXT: @escaping @MainActor (String, [String: String]) -> Void) {
            self.onTXT = onTXT
        }

        func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
            let name = sender.name
            let parsed = MDNSDiscovery.parseTXTRecord(data)
            guard !parsed.isEmpty else { return }
            Task { @MainActor [onTXT] in onTXT(name, parsed) }
        }
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
        for q in deviceInfoQueries.values { q.stop() }
        deviceInfoQueries.removeAll()
        deviceInfoIPs.removeAll()
        seenEndpoints.removeAll()
    }

    // MARK: - Device info

    /// Asks `name` what hardware it is.
    ///
    /// Fired once a browsable service has told us both the instance name and the IP behind it —
    /// `_device-info._tcp` can answer this question but cannot be found, so something else has to
    /// introduce them first.
    private func queryDeviceInfo(name: String, ip: String) {
        guard deviceInfoIPs[name] == nil else { return }
        deviceInfoIPs[name] = ip

        let service = NetService(domain: "local.", type: Self.deviceInfoType, name: name)
        service.delegate = deviceInfoDelegate
        deviceInfoQueries[name] = service
        service.schedule(in: .main, forMode: .common)
        service.startMonitoring()
    }

    private func receiveDeviceInfo(name: String, txt: [String: String]) {
        guard let ip = deviceInfoIPs[name] else { return }
        deviceInfoByIP[ip] = txt
    }

    /// `NetService`'s TXT format is `[String: Data]`; the rules want strings.
    ///
    /// nonisolated: the NetService delegate callback arrives outside the main actor, and parsing a
    /// dictionary touches nothing this class owns.
    nonisolated static func parseTXTRecord(_ data: Data) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in NetService.dictionary(fromTXTRecord: data) {
            guard let string = String(data: value, encoding: .utf8) else { continue }
            out[key.lowercased()] = string
        }
        return out
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

    /// TXT records for `ip`, merged across its services, with device-info on top.
    ///
    /// Device-info wins the `model` key deliberately. A service's own TXT can carry a `model` too,
    /// and it describes the *service* — an AirPlay receiver's model, a printer's. Only
    /// `_device-info._tcp` is the host stating its own hardware, which is what the apple.model.*
    /// rules are asking about.
    func txt(for ip: String) -> [String: String] {
        var merged: [String: String] = [:]
        for record in services(for: ip) {
            merged.merge(record.txt) { existing, _ in existing }
        }
        merged.merge(deviceInfoByIP[ip] ?? [:]) { _, deviceInfo in deviceInfo }
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
        // Every browsable service is an introduction to the host's device-info record, which cannot
        // be found any other way. Deduped inside — a Mac publishing six services asks once.
        queryDeviceInfo(name: record.name, ip: record.ip)
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
