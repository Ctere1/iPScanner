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

    private(set) var servicesByIP: [String: Set<ServiceRecord>] = [:]
    private var browsers: [NWBrowser] = []
    private var connections: [String: NWConnection] = [:]
    private var inventory = BonjourInventory()
    private var monitor: NWPathMonitor?
    private var networkFingerprint: String?
    private var generation = UUID()
    private let resolveQueue = DispatchQueue(label: "iPScanner.mdns", attributes: .concurrent)
    var isRunning: Bool { !browsers.isEmpty }

    func start() {
        guard !isRunning else { return }
        let run = UUID(); generation = run
        for (type, label) in Self.serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.handle(results: results, type: type, displayType: label, run: run)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                let addresses = NetworkInterface.scannableInterfaces().map { "\($0.name):\($0.ipv4)/\($0.netmaskBits)" }.sorted().joined(separator: ",")
                let fingerprint = "\(path.status):\(addresses)"
                if let previous = self.networkFingerprint, previous != fingerprint {
                    self.stop(); self.start()
                } else { self.networkFingerprint = fingerprint }
            }
        }
        monitor.start(queue: resolveQueue)
    }

    func stop() {
        generation = UUID()
        for browser in browsers { browser.cancel() }
        browsers.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        inventory = BonjourInventory()
        servicesByIP = [:]
        monitor?.cancel(); monitor = nil; networkFingerprint = nil
    }

    func services(for ip: String) -> [ServiceRecord] {
        Array(servicesByIP[ip] ?? []).sorted { ($0.displayType, $0.name) < ($1.displayType, $1.name) }
    }
    func uniqueServiceTypes(for ip: String) -> [String] { Array(Set(services(for: ip).map(\.displayType))).sorted() }

    private func handle(results: Set<NWBrowser.Result>, type: String, displayType: String, run: UUID) {
        var endpoints: [String: (NWEndpoint, String)] = [:]
        for result in results {
            guard case .service(let name, _, let domain, let interface) = result.endpoint else { continue }
            let id = "\(type)|\(domain)|\(name)|\(interface?.index ?? 0)"
            endpoints[id] = (result.endpoint, name)
        }
        let removed = inventory.reconcile(ids: Set(endpoints.keys), type: type)
        for id in removed { connections.removeValue(forKey: id)?.cancel() }
        rebuild()
        for (id, value) in endpoints where connections[id] == nil && inventory.records[id] == nil {
            guard let token = inventory.tokens[id] else { continue }
            let connection = NWConnection(to: value.0, using: .tcp)
            connections[id] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let connection else { return }
                switch state {
                case .ready:
                    let host: NWEndpoint.Host?
                    if let path = connection.currentPath, case .hostPort(let remote, _) = path.remoteEndpoint { host = remote } else { host = nil }
                    let ip = host.flatMap(Self.ipv4String)
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        if let ip { self.inventory.accept(.init(displayType: displayType, serviceType: type, name: value.1, ip: ip), id: id, token: token) }
                        self.rebuild()
                        if self.connections[id] === connection { self.connections.removeValue(forKey: id) }
                        connection.cancel()
                    }
                case .failed, .cancelled:
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        if self.connections[id] === connection { self.connections.removeValue(forKey: id) }
                    }
                default: break
                }
            }
            connection.start(queue: resolveQueue)
            Task { @MainActor [weak self, weak connection] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let connection, self.generation == run, self.connections[id] === connection else { return }
                self.connections.removeValue(forKey: id); connection.cancel()
            }
        }
    }
    private func rebuild() {
        servicesByIP = Dictionary(grouping: inventory.records.values, by: \.ip).mapValues(Set.init)
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


// Reconciles complete browser snapshots and rejects a late resolution after removal.
struct BonjourInventory {
    private(set) var tokens: [String: UUID] = [:]
    private(set) var records: [String: MDNSDiscovery.ServiceRecord] = [:]
    mutating func reconcile(ids: Set<String>, type: String) -> Set<String> {
        let previous = Set(tokens.keys.filter { $0.hasPrefix(type + "|") })
        let removed = previous.subtracting(ids)
        for id in removed { tokens.removeValue(forKey: id); records.removeValue(forKey: id) }
        for id in ids where tokens[id] == nil { tokens[id] = UUID() }
        return removed
    }
    mutating func accept(_ record: MDNSDiscovery.ServiceRecord, id: String, token: UUID) {
        guard tokens[id] == token else { return }
        records[id] = record
    }
}
