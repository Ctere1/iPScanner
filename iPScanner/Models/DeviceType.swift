import Foundation

enum DeviceType: String, Hashable, CaseIterable, Sendable {
    case router
    case accessPoint
    case printer
    case camera
    case tv
    case speaker
    case gameConsole
    case mac
    case phone
    case tablet
    case watch
    case appleTV
    case homePod
    case nas
    case windows
    case linux
    case server
    case iot
    case unknown

    /// How specific a verdict this is, low to high. Breaks a scoring tie toward the answer that
    /// says more: "printer" and "server" tied means printer, because everything serves something.
    var specificity: Int {
        switch self {
        case .printer, .camera, .appleTV, .homePod, .watch, .gameConsole: 0
        case .phone, .tablet, .speaker, .nas, .accessPoint: 1
        case .tv, .router, .mac: 2
        case .windows, .iot: 3
        case .linux: 4
        case .server: 5
        case .unknown: 6
        }
    }

    /// SF Symbol name. A plain string rather than an `Image` so `Models/` stays free of SwiftUI —
    /// the CLI compiles this file too. The colour half lives in App/Presentation.
    var sfSymbol: String {
        switch self {
        case .router: "wifi.router"
        case .accessPoint: "wifi"
        case .printer: "printer"
        case .camera: "video"
        case .tv: "tv"
        case .speaker: "hifispeaker"
        case .gameConsole: "gamecontroller"
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .watch: "applewatch"
        case .appleTV: "appletv"
        case .homePod: "homepod"
        case .nas: "externaldrive.connected.to.line.below"
        case .windows: "pc"
        case .linux: "terminal"
        case .server: "server.rack"
        case .iot: "homekit"
        case .unknown: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .router: "Router"
        case .accessPoint: "Access Point"
        case .printer: "Printer"
        case .camera: "Camera"
        case .tv: "TV"
        case .speaker: "Speaker"
        case .gameConsole: "Game Console"
        case .mac: "Mac"
        case .phone: "Phone"
        case .tablet: "Tablet"
        case .watch: "Watch"
        case .appleTV: "Apple TV"
        case .homePod: "HomePod"
        case .nas: "NAS"
        case .windows: "Windows"
        case .linux: "Linux"
        case .server: "Server"
        case .iot: "IoT"
        case .unknown: "—"
        }
    }
}

/// How much to trust a verdict.
enum DeviceConfidence: Int, Comparable, Hashable, Sendable {
    case none
    case low
    case medium
    case high

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none: "Unknown"
        case .low: "Low confidence"
        case .medium: "Likely"
        case .high: "Confident"
        }
    }
}

/// A verdict, with the evidence behind it.
struct DeviceClassification: Equatable, Hashable, Sendable {
    var type: DeviceType = .unknown
    var confidence: DeviceConfidence = .none
    var score: Int = 0
    /// Ids of the rules that fired for `type` — what the inspector shows when asked "why?".
    var matchedRuleIDs: [String] = []

    static let unknown = DeviceClassification()
}
