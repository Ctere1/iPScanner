import XCTest
@testable import iPScanner

/// The old test factory could not set ttl, netbiosName or workgroup — which is exactly why those
/// three signals stayed dead in the classifier for as long as they did, and why `.server`, `.iot`
/// and `.windows` had no tests at all. This builds signals directly.
final class DeviceClassifierTests: XCTestCase {

    private func signals(
        ports: [Int] = [],
        mdns: [String] = [],
        txt: [String: String] = [:],
        vendor: String? = nil,
        hostname: String? = nil,
        title: String? = nil,
        ttl: Int? = nil,
        netbios: String? = nil,
        workgroup: String? = nil,
        gateway: Bool = false
    ) -> DeviceSignals {
        DeviceSignals(
            ip: "10.0.0.5",
            vendor: vendor,
            hostname: hostname,
            netbiosName: netbios,
            workgroup: workgroup,
            serviceTitle: title,
            ttl: ttl,
            openPorts: Set(ports),
            scannedPorts: Set(ports),
            mdnsTypes: Set(mdns),
            mdnsTXT: txt,
            isDefaultGateway: gateway
        )
    }

    private func type(_ s: DeviceSignals) -> DeviceType {
        DeviceClassifier.live.classify(s).type
    }

    // MARK: - Shadowing
    //
    // None of this had any coverage. The old chain tested `.server` (port 22/80/443/8080) before
    // `.iot`, so the IoT branch was unreachable for anything with a web UI.

    func testIoTVendorWithWebUIIsNotAServer() {
        XCTAssertEqual(type(signals(ports: [80], vendor: "Espressif Inc.")), .iot)
    }

    func testHueBridgeIsIoTNotServer() {
        XCTAssertEqual(type(signals(ports: [80, 443], mdns: ["_hue._tcp"], vendor: "Signify")), .iot)
    }

    func testShellyIsIoTNotServer() {
        XCTAssertEqual(type(signals(ports: [80], vendor: "Allterco Robotics")), .iot)
    }

    /// "Server" now means what the word means, rather than "answered on 80".
    func testSSHPlusWebIsAServer() {
        XCTAssertEqual(type(signals(ports: [22, 80])), .server)
    }

    /// One open web port identifies nothing. An honest dash beats a confident lie.
    func testLoneWebPortIsUnknown() {
        XCTAssertEqual(type(signals(ports: [80])), .unknown)
    }

    func testLoneSSHIsUnknown() {
        XCTAssertEqual(type(signals(ports: [22])), .unknown)
    }

    // MARK: - Substring false positives
    //
    // All of these were wrong before, and all for the same reason: `.contains` on a hostname.

    func testNatviewIsNotATV() {
        XCTAssertNotEqual(type(signals(hostname: "natview")), .tv, "\"natview\" contains \"tv\"")
    }

    func testJonasPCIsNotANAS() {
        XCTAssertNotEqual(type(signals(hostname: "jonas-pc")), .nas, "\"jonas-pc\" contains \"nas\"")
    }

    func testAtlasNasaHostIsNotANAS() {
        XCTAssertNotEqual(type(signals(hostname: "atlas-nasa-lab")), .nas)
    }

    /// macOS runs CUPS and listens on 631. It is not a printer.
    func testAppleHostWithCUPSIsNotAPrinter() {
        let s = signals(ports: [631], mdns: ["_workstation._tcp"], vendor: "Apple, Inc.")
        XCTAssertNotEqual(type(s), .printer)
    }

    /// macOS AirPlay Receiver listens on 5000. It is not a Synology.
    func testAppleHostOnPort5000IsNotANAS() {
        let s = signals(ports: [5000], mdns: ["_workstation._tcp"], vendor: "Apple, Inc.")
        XCTAssertNotEqual(type(s), .nas)
    }

    /// Found on a real network: a Mac with AirPlay Receiver on, scanned by the CLI — which has no
    /// OUI data, so the vendor guard above could not fire — came back as a NAS. 5000 alongside 7000
    /// is AirPlay's pair, and no Synology opens 7000.
    func testAirPlayPairIsNotANASEvenWithoutAVendor() {
        XCTAssertNotEqual(type(signals(ports: [5000, 7000])), .nas)
    }

    /// The port 5000 that really is a Synology still reads as one.
    func testPort5000WithoutAirPlayIsStillANAS() {
        XCTAssertEqual(type(signals(ports: [5000, 445])), .nas)
    }

    /// Bare "philips" used to mean IoT, which made every Philips television a light bulb.
    func testPhilipsTVIsATVNotIoT() {
        XCTAssertEqual(type(signals(mdns: ["_googlecast._tcp"], vendor: "Philips TV")), .tv)
    }

    /// Samsung sells phones as well as televisions.
    func testSamsungPhoneIsNotATV() {
        XCTAssertNotEqual(type(signals(vendor: "Samsung Electronics", hostname: "galaxy-s23")), .tv)
    }

    // MARK: - Apple, via _device-info._tcp
    //
    // The strongest signal on the LAN, and previously discarded: every Apple-vendor host that was
    // not literally named "iphone" came back as a Mac.

    func testModelSaysIPhone() {
        let s = signals(mdns: ["_device-info._tcp"], txt: ["model": "iPhone15,2"], vendor: "Apple, Inc.")
        XCTAssertEqual(type(s), .phone)
    }

    func testModelSaysMacBook() {
        let s = signals(txt: ["model": "MacBookPro18,3"], vendor: "Apple, Inc.")
        XCTAssertEqual(type(s), .mac)
    }

    func testModelSaysAppleTV() {
        let s = signals(mdns: ["_airplay._tcp"], txt: ["model": "AppleTV11,1"], vendor: "Apple, Inc.")
        XCTAssertEqual(type(s), .appleTV)
    }

    func testModelSaysHomePod() {
        let s = signals(mdns: ["_raop._tcp"], txt: ["model": "AudioAccessory5,1"], vendor: "Apple, Inc.")
        XCTAssertEqual(type(s), .homePod)
    }

    func testModelSaysIPad() {
        XCTAssertEqual(type(signals(txt: ["model": "iPad13,1"], vendor: "Apple, Inc.")), .tablet)
    }

    func testModelSaysWatch() {
        XCTAssertEqual(type(signals(txt: ["model": "Watch6,1"], vendor: "Apple, Inc.")), .watch)
    }

    func testTXTKeysAreCaseInsensitive() {
        XCTAssertEqual(type(signals(txt: ["MODEL": "iPhone15,2"])), .phone)
    }

    /// lockdownd runs on every iOS device and no Mac.
    func testLockdownPortMeansIOS() {
        XCTAssertEqual(type(signals(ports: [62078], vendor: "Apple, Inc.")), .phone)
    }

    // MARK: - TTL
    //
    // Collected since TTL was added to Host, and never read by the classifier until now.

    func testWindowsTTLWithSMB() {
        let s = signals(ports: [445, 139], ttl: 128, workgroup: "WORKGROUP")
        XCTAssertEqual(type(s), .windows)
    }

    /// TTL is `initial - hops`, so a few routers away still reads as Windows.
    func testWindowsTTLSurvivesAFewHops() {
        XCTAssertEqual(type(signals(ports: [445, 139], ttl: 122)), .windows)
    }

    func testNetworkGearTTL() {
        XCTAssertEqual(type(signals(ttl: 250)), .router)
    }

    func testLinuxTTLWithSSH() {
        XCTAssertEqual(type(signals(ports: [22], ttl: 64)), .linux)
    }

    /// The TCP fallback path reports no TTL. These rules must contribute nothing rather than guess.
    func testAbsentTTLContributesNothing() {
        XCTAssertEqual(type(signals(ttl: nil)), .unknown)
    }

    func testTTLWindowsDoNotOverlap() {
        XCTAssertNotEqual(type(signals(ports: [22], ttl: 64)), .windows)
        XCTAssertNotEqual(type(signals(ttl: 250)), .windows)
    }

    // MARK: - NetBIOS

    /// A workgroup is a Windows concept; nothing else publishes one.
    func testWorkgroupIsWindowsEvidence() {
        let s = signals(ports: [445], ttl: 128, netbios: "OFFICE-PC", workgroup: "WORKGROUP")
        XCTAssertEqual(type(s), .windows)
    }

    /// The NetBIOS name is often the only name a Windows box offers, so it is tokenised too.
    func testNetBIOSNameIsTokenised() {
        XCTAssertTrue(signals(netbios: "OFFICE-PC").hostnameTokens.contains("office"))
    }

    // MARK: - Gateway

    func testTheGatewayIsARouter() {
        XCTAssertEqual(type(signals(ports: [80], gateway: true)), .router)
    }

    // MARK: - Printers

    func testRawPort9100IsDecisive() {
        XCTAssertEqual(type(signals(ports: [9100])), .printer)
    }

    func testPrinterByBonjour() {
        XCTAssertEqual(type(signals(mdns: ["_ipp._tcp", "_pdl-datastream._tcp"])), .printer)
    }

    func testPrinterByVendor() {
        for vendor in ["Hewlett Packard", "Brother Industries", "Canon Inc.", "Seiko Epson"] {
            XCTAssertEqual(type(signals(vendor: vendor)), .printer, vendor)
        }
    }

    // MARK: - Other categories

    func testChromecast() {
        XCTAssertEqual(type(signals(mdns: ["_googlecast._tcp"])), .tv)
    }

    func testCameraByRTSP() {
        XCTAssertEqual(type(signals(ports: [554, 80])), .camera)
    }

    func testCameraByVendor() {
        XCTAssertEqual(type(signals(vendor: "Hangzhou Hikvision Digital Technology")), .camera)
    }

    func testSynologyNAS() {
        XCTAssertEqual(type(signals(ports: [5000, 445], vendor: "Synology Incorporated")), .nas)
    }

    func testSonosIsASpeaker() {
        XCTAssertEqual(type(signals(mdns: ["_raop._tcp"], vendor: "Sonos, Inc.")), .speaker)
    }

    func testUbiquitiIsAnAccessPoint() {
        XCTAssertEqual(type(signals(vendor: "Ubiquiti Networks")), .accessPoint)
    }

    func testGameConsole() {
        XCTAssertEqual(type(signals(hostname: "PlayStation-5")), .gameConsole)
    }

    // MARK: - Engine

    func testEmptySignalsAreUnknown() {
        XCTAssertEqual(type(signals()), .unknown)
        XCTAssertEqual(DeviceClassifier.live.classify(signals()).confidence, .none)
    }

    func testMatchedRuleIDsExplainTheVerdict() {
        let result = DeviceClassifier.live.classify(signals(ports: [9100]))
        XCTAssertEqual(result.type, .printer)
        XCTAssertTrue(result.matchedRuleIDs.contains("printer.port.raw9100"))
    }

    func testMatchedRuleIDsOnlyCoverTheWinner() {
        let result = DeviceClassifier.live.classify(signals(ports: [9100, 80]))
        XCTAssertEqual(result.type, .printer)
        XCTAssertFalse(result.matchedRuleIDs.contains { $0.hasPrefix("server.") })
    }

    func testDecisiveEvidenceIsConfident() {
        let result = DeviceClassifier.live.classify(
            signals(mdns: ["_device-info._tcp"], txt: ["model": "iPhone15,2"], hostname: "cemils-iphone")
        )
        XCTAssertEqual(result.type, .phone)
        XCTAssertEqual(result.confidence, .high)
    }

    /// A contested verdict must not claim confidence it does not have.
    func testContestedEvidenceIsNotConfident() {
        let result = DeviceClassifier.live.classify(signals(ports: [22, 80]))
        XCTAssertEqual(result.type, .server)
        XCTAssertLessThan(result.confidence, .high)
    }

    func testNegativeWeightsSubtract() {
        // Apple vendor argues against Windows, so an SMB stack alone must not win outright.
        let appleish = signals(ports: [445, 135], vendor: "Apple, Inc.", ttl: 64)
        XCTAssertNotEqual(type(appleish), .windows)
    }

    /// A tie goes to the answer that says more.
    func testTiesBreakTowardSpecificity() {
        XCTAssertLessThan(DeviceType.printer.specificity, DeviceType.server.specificity)
        XCTAssertLessThan(DeviceType.camera.specificity, DeviceType.linux.specificity)
        XCTAssertEqual(DeviceType.unknown.specificity, DeviceType.allCases.map(\.specificity).max())
    }

    /// Guards the table as it grows: a duplicated id makes `matchedRuleIDs` ambiguous and usually
    /// means a rule was copy-pasted and not renamed.
    func testRuleIDsAreUnique() {
        let ids = DeviceRules.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate rule id")
    }

    func testEveryDeviceTypeHasSymbolAndLabel() {
        for type in DeviceType.allCases {
            XCTAssertFalse(type.sfSymbol.isEmpty, "\(type) has no symbol")
            XCTAssertFalse(type.label.isEmpty, "\(type) has no label")
        }
    }

    /// The realistic default-profile host before the fingerprint phase existed: pinged, enriched,
    /// no ports. It is the case the whole redesign is aimed at.
    func testPingOnlyHostWithVendorStillIdentifies() {
        XCTAssertEqual(type(signals(vendor: "Hewlett Packard")), .printer)
    }
}
