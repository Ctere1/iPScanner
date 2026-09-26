import Foundation

enum DeviceType: String, Hashable {
    case router
    case printer
    case tv
    case mac
    case phone
    case server
    case nas
    case iot
    case windows
    case unknown

    var sfSymbol: String {
        switch self {
        case .router: "wifi.router"
        case .printer: "printer"
        case .tv: "tv"
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .iot: "homekit"
        case .windows: "pc"
        case .unknown: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .router: "Router"
        case .printer: "Printer"
        case .tv: "TV"
        case .mac: "Mac"
        case .phone: "Phone"
        case .server: "Server"
        case .nas: "NAS"
        case .iot: "IoT"
        case .windows: "Windows"
        case .unknown: "Unknown"
        }
    }
}

struct DeviceClassification {
    let type: DeviceType
    let evidence: String
}

enum DeviceClassifier {
    static func classify(_ host: Host) -> DeviceType { assessment(host).type }

    static func assessment(_ host: Host) -> DeviceClassification {
        // A DNS search suffix belongs to the network, not the device.
        let name = (host.hostname ?? "").lowercased().split(separator: ".").first.map(String.init) ?? ""
        let vendor = (host.vendor ?? "").lowercased()
        let title = (host.serviceTitle ?? "").lowercased()
        let ports = Set(host.openPorts)
        var evidence: [DeviceType: [String]] = [:]
        func add(_ type: DeviceType, _ reason: String) { evidence[type, default: []].append(reason) }
        if name.contains("iphone") || name.contains("ipad") || name.contains("android") { add(.phone, "Device name identifies a phone or tablet") }
        if name.contains("macbook") || name.contains("imac") || name == "mac" || name.hasSuffix("-mbp") { add(.mac, "Device name identifies a Mac") }
        if name.contains("printer") || title.contains("laserjet") || title.contains("officejet") { add(.printer, "Printer name or service title") }
        if ports.contains(9100) || ports.contains(515) { add(.printer, "Printing service port") }
        if ports.contains(631) && (vendor.contains("brother") || vendor.contains("canon") || name.contains("print")) { add(.printer, "IPP with a printer identity") }
        if name == "tv" || name.hasSuffix("-tv") || name.hasPrefix("tv-") || title.contains("smart tv") { add(.tv, "TV name or service title") }
        if ["router", "gateway", "hgw"].contains(name) || name.hasSuffix("-router") { add(.router, "Router device name") }
        if name == "nas" || name.hasSuffix("-nas") || ((vendor.contains("synology") || vendor.contains("qnap")) && !ports.intersection([445, 5000, 5001, 2049]).isEmpty) { add(.nas, "NAS identity and storage service") }
        if ports.contains(445) && (ports.contains(135) || ports.contains(139)) { add(.windows, "SMB and Windows RPC/NetBIOS services") }
        if (vendor.contains("espressif") || vendor.contains("tuya") || vendor.contains("sonoff")) && !ports.isEmpty { add(.iot, "Embedded-device vendor with a reachable service") }
        guard evidence.count == 1, let match = evidence.first else {
            return .init(type: .unknown, evidence: evidence.isEmpty ? "Not enough evidence to identify the device type." : "Conflicting device hints; type left unknown.")
        }
        return .init(type: match.key, evidence: match.value.joined(separator: "; ") + ". This is an estimate.")
    }
}
