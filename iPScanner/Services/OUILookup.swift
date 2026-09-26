import Foundation

final class OUILookup: @unchecked Sendable {
    static let shared = OUILookup()

    private let mal: [String: String]   // 24-bit prefixes (6 hex chars)
    private let mam: [String: String]   // 28-bit prefixes (7 hex chars)
    private let mas: [String: String]   // 36-bit prefixes (9 hex chars)

    private let databaseAvailable: Bool
    private struct Registry: Decodable {
        let version: Int
        let mal: [String: String]
        let mam: [String: String]
        let mas: [String: String]
    }
    private init() {
        if let text = Self.loadFile("vendors", ext: "json"),
           let data = text.data(using: .utf8),
           let registry = try? JSONDecoder().decode(Registry.self, from: data),
           registry.version == 1, !registry.mal.isEmpty, !registry.mam.isEmpty, !registry.mas.isEmpty {
            mas = registry.mas; mam = registry.mam; mal = registry.mal
            databaseAvailable = true
        } else {
            mas = [:]; mam = [:]; mal = [:]
            databaseAvailable = false
        }
    }

    /// Test-only initializer that bypasses the bundled OUI files.
    init(mas: [String: String], mam: [String: String], mal: [String: String]) {
        self.mas = mas
        self.databaseAvailable = true
        self.mam = mam
        self.mal = mal
    }

    func resolve(_ raw: String?) -> VendorResolution {
        guard let raw else { return .init(vendor: nil, status: .macUnavailable) }
        guard let mac = MACAddress(raw) else { return .init(vendor: nil, status: .invalidAddress) }
        switch mac.kind {
        case .local: return .init(vendor: nil, status: .localAddress)
        case .multicast, .broadcast: return .init(vendor: nil, status: .nonUnicast)
        case .universal: break
        }
        guard databaseAvailable else { return .init(vendor: nil, status: .databaseUnavailable) }
        let key = mac.hex
        let vendor = mas[String(key.prefix(9))] ?? mam[String(key.prefix(7))] ?? mal[String(key.prefix(6))]
        return .init(vendor: vendor, status: vendor == nil ? .notFound : .matched)
    }

    func vendor(forMAC mac: String) -> String? { resolve(mac).vendor }
    static func normalizedHex(_ mac: String) -> String { MACAddress(mac)?.hex ?? "" }

    // MARK: - Parsers

    private static func parseMAL(filename: String) -> [String: String] {
        guard let content = loadFile(filename) else { return [:] }
        return parseMAL(content: content)
    }

    static func parseMAL(content: String) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(40_000)
        // IEEE files contain hundreds of thousands of address lines. Only parse
        // assignment records; avoid running a regex engine on every line.
        for line in content.split(whereSeparator: \.isNewline) {
            guard let marker = line.range(of: "(hex)") else { continue }
            let prefix = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "-", with: "").uppercased()
            let vendor = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            guard validHex(prefix, length: 6), !vendor.isEmpty else { continue }
            result[prefix] = vendor
        }
        return result
    }

    private static func parseSubBlock(filename: String, subPrefixHexLength: Int) -> [String: String] {
        guard let content = loadFile(filename) else { return [:] }
        return parseSubBlock(content: content, subPrefixHexLength: subPrefixHexLength)
    }

    static func parseSubBlock(content: String, subPrefixHexLength: Int) -> [String: String] {
        guard subPrefixHexLength == 1 || subPrefixHexLength == 3 else { return [:] }
        var result: [String: String] = [:]
        var lastOUI: String?
        for line in content.split(whereSeparator: \.isNewline) {
            if let marker = line.range(of: "(hex)") {
                let prefix = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "-", with: "").uppercased()
                lastOUI = validHex(prefix, length: 6) ? prefix : nil
            } else if let marker = line.range(of: "(base 16)"), let oui = lastOUI {
                let bounds = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                    .uppercased().split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2, validHex(String(bounds[0]), length: 6),
                      validHex(String(bounds[1]), length: 6) else { continue }
                let vendor = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
                if !vendor.isEmpty { result[oui + bounds[0].prefix(subPrefixHexLength)] = vendor }
            }
        }
        return result
    }

    private static func validHex(_ string: String, length: Int) -> Bool {
        string.utf8.count == length && string.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0)
        }
    }

    private static func loadFile(_ name: String, ext: String = "txt") -> String? {
        for url in candidateURLs(for: name, ext: ext) {
            if let data = try? Data(contentsOf: url) {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// Search paths the OUI files might live in. Ordered by likelihood.
    /// Lets the same loader work from inside the app bundle and from the
    /// `ipscanner` CLI binary distributed in `Contents/Helpers/`.
    private static func candidateURLs(for name: String, ext: String) -> [URL] {
        var urls: [URL] = []
        // 1. Standard app-bundle resource lookup (works for the GUI app).
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            urls.append(url)
        }
        let fileName = "\(name).\(ext)"
        // 2. Sibling of the executable: `Contents/Helpers/ipscanner` → `Contents/Resources/oui.txt`.
        let exeDir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath().deletingLastPathComponent()
        let bundleResources = exeDir.deletingLastPathComponent().appendingPathComponent("Resources")
        urls.append(bundleResources.appendingPathComponent(fileName))
        // 3. Same directory as the binary (loose distribution).
        urls.append(exeDir.appendingPathComponent(fileName))
        // 4. Current working directory (developer convenience).
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(fileName))
        return urls
    }
}
