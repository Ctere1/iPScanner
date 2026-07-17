import Foundation

/// The evidence table. Data, not control flow — the engine in DeviceClassifier scores it.
enum DeviceRules {
    /// Vendors that make small connected things. Referenced by the server rule too, to keep a
    /// light bulb with a web UI from being called a server.
    static let iotVendors = [
        "espressif", "tuya", "sonoff", "itead", "shelly", "allterco", "xiaomi", "yeelight",
        "signify", "philips lighting", "nest labs", "amazon technologies", "wyze",
        "ikea of sweden", "aqara", "lumi", "broadlink", "ecobee", "wemo", "belkin"
    ]

    static let all: [DeviceRule] = printers + apple + castAndTV + nas + routers + windowsLinux
        + cameras + iot + consoles + servers

    // MARK: - Printers

    static let printers: [DeviceRule] = [
        DeviceRule("printer.port.raw9100", .printer, W.decisive, .port(9100)),
        DeviceRule("printer.mdns.pdl", .printer, W.decisive, .mdns("_pdl-datastream._tcp")),
        DeviceRule("printer.mdns.printer", .printer, W.decisive, .mdns("_printer._tcp")),
        DeviceRule("printer.mdns.ipp", .printer, W.strong, .anyMDNS(["_ipp._tcp", "_ipps._tcp"])),
        DeviceRule("printer.port.lpd515", .printer, W.strong, .port(515)),
        DeviceRule("printer.vendor", .printer, W.strong, .anyDescrPhrase([
            "hewlett", "hp inc", "brother", "canon", "seiko epson", "epson", "lexmark",
            "xerox", "ricoh", "kyocera", "oki ", "konica", "zebra", "dymo"
        ])),
        // 631 is IPP, but macOS runs CUPS and listens on it too. Alone it is not a printer.
        DeviceRule("printer.port.ipp631", .printer, W.moderate,
                   .all([.port(631), .not(.descrPhrase("apple"))])),
        DeviceRule("printer.title", .printer, W.moderate, .anyDescrPhrase([
            "laserjet", "officejet", "deskjet", "pixma", "imageclass", "workforce", "ecosys",
            "mfc-", "dcp-", "jetdirect"
        ])),
        DeviceRule("printer.host", .printer, W.moderate,
                   .anyHostToken(["printer", "print", "laserjet", "officejet"])),
        // sysDescr on a network printer is unmistakable: "HP ETHERNET MULTI-ENVIRONMENT".
        DeviceRule("printer.snmp", .printer, W.strong,
                   .anyDescrPhrase(["ethernet multi-environment", "printer mib", "jetdirect"]))
    ]

    // MARK: - Apple
    //
    // `_device-info._tcp` publishes `model=`, which names the hardware exactly. Nothing else on a
    // LAN is this precise, and it arrives free with the Bonjour browse. Before it was captured,
    // every Apple-vendor host that was not literally named "iphone" was called a Mac — which is
    // why an Apple TV, a HomePod and an iPhone with a real name all showed the same icon.

    static let apple: [DeviceRule] = [
        DeviceRule("apple.model.iphone", .phone, W.decisive, .mdnsTXT(key: "model", hasPrefix: "iPhone")),
        DeviceRule("apple.model.ipad", .tablet, W.decisive, .mdnsTXT(key: "model", hasPrefix: "iPad")),
        DeviceRule("apple.model.watch", .watch, W.decisive, .mdnsTXT(key: "model", hasPrefix: "Watch")),
        DeviceRule("apple.model.appletv", .appleTV, W.decisive, .any([
            .mdnsTXT(key: "model", hasPrefix: "AppleTV"),
            .mdnsTXT(key: "model", hasPrefix: "J305"),
            .mdnsTXT(key: "model", hasPrefix: "J255")
        ])),
        DeviceRule("apple.model.homepod", .homePod, W.decisive, .any([
            .mdnsTXT(key: "model", hasPrefix: "AudioAccessory"),
            .mdnsTXT(key: "model", hasPrefix: "HomePod")
        ])),
        DeviceRule("apple.model.mac", .mac, W.decisive, .any([
            .mdnsTXT(key: "model", hasPrefix: "MacBook"),
            .mdnsTXT(key: "model", hasPrefix: "iMac"),
            .mdnsTXT(key: "model", hasPrefix: "Macmini"),
            .mdnsTXT(key: "model", hasPrefix: "MacPro"),
            .mdnsTXT(key: "model", hasPrefix: "Mac")
        ])),
        // Demoted from a full verdict: Apple sells phones, watches and speakers too.
        DeviceRule("apple.vendor", .mac, W.weak, .descrPhrase("apple")),
        // lockdownd. No Mac has it; every iPhone and iPad does.
        DeviceRule("apple.port.lockdown", .phone, 5, .port(62078)),
        DeviceRule("apple.mdns.workstation", .mac, W.moderate, .mdns("_workstation._tcp")),
        DeviceRule("apple.mdns.rfb", .mac, W.weak, .mdns("_rfb._tcp")),
        DeviceRule("apple.mdns.companion", .mac, W.hint, .mdns("_companion-link._tcp")),
        DeviceRule("apple.host.iphone", .phone, W.strong, .anyHostToken(["iphone"])),
        DeviceRule("apple.host.ipad", .tablet, W.strong, .anyHostToken(["ipad"])),
        DeviceRule("apple.host.mac", .mac, W.moderate,
                   .anyHostToken(["macbook", "imac", "macmini", "macstudio", "mbp", "mba"])),
        DeviceRule("android.host", .phone, W.moderate,
                   .anyHostToken(["android", "pixel", "galaxy", "oneplus"]))
    ]

    // MARK: - Cast / TV / speakers

    static let castAndTV: [DeviceRule] = [
        DeviceRule("cast.mdns", .tv, 5, .mdns("_googlecast._tcp")),
        DeviceRule("cast.port.8009", .tv, W.strong, .port(8009)),
        DeviceRule("cast.descr", .tv, W.strong,
                   .anyDescrPhrase(["chromecast", "google cast", "android tv", "fire tv", "roku"])),
        DeviceRule("airplay.mdns", .appleTV, W.strong, .mdns("_airplay._tcp")),
        DeviceRule("airplay.port.7000", .appleTV, W.weak, .port(7000)),
        //
        // There is deliberately no rule here for "5000 and 7000 open".
        //
        // That pair means AirPlay is listening, which is true of an Apple TV *and* of any Mac with
        // AirPlay Receiver switched on — so it cannot name either one. An earlier attempt scored it
        // for .appleTV and got a MacBook wrong: the Mac's own evidence (Apple vendor + TTL 64)
        // tied with it, and a tie breaks toward the more specific type, so the Mac lost to a device
        // it merely shares a port with. An Apple TV is identified by what it advertises —
        // `model=AppleTV*` or `_airplay._tcp` — not by a port a laptop also opens.
        //
        // The pair does still do one job: it guards the NAS rule below, where 5000 alone would
        // otherwise read as Synology's web UI.
        DeviceRule("raop.mdns", .speaker, W.moderate, .mdns("_raop._tcp")),
        DeviceRule("speaker.vendor", .speaker, W.strong,
                   .anyDescrPhrase(["sonos", "bose", "denon", "yamaha", "harman", "marshall"])),
        DeviceRule("speaker.mdns", .speaker, 5,
                   .anyMDNS(["_sonos._tcp", "_spotify-connect._tcp"])),
        // Two vendors are deliberately missing from this list.
        //
        // "philips" bare is under IoT as "philips lighting"/"signify" — the unqualified string used
        // to make every Philips television a light bulb.
        //
        // "samsung electronics" is absent because that OUI covers phones, SSDs, monitors and
        // fridges as readily as televisions: it is not evidence of anything. A Samsung TV is
        // identified the way any other TV is — by Cast, AirPlay, Tizen, or its own name.
        DeviceRule("tv.vendor", .tv, W.strong, .anyDescrPhrase([
            "vestel", "lg electronics", "tcl", "hisense", "philips tv",
            "sony", "panasonic", "arcelik", "beko"
        ])),
        DeviceRule("tv.title", .tv, W.moderate,
                   .anyDescrPhrase(["smart tv", "webos", "tizen", "bravia", "viera"])),
        // Whole token: "natview" no longer becomes a television.
        DeviceRule("tv.host", .tv, W.moderate, .anyHostToken(["tv", "smarttv", "androidtv"])),
        DeviceRule("cast.ssdp.dial", .tv, W.moderate, .descrPhrase("urn:dial-multiscreen-org")),
        DeviceRule("tv.ssdp.renderer", .tv, W.moderate,
                   .descrPhrase("urn:schemas-upnp-org:device:mediarenderer"))
    ]

    // MARK: - NAS

    static let nas: [DeviceRule] = [
        DeviceRule("nas.vendor", .nas, 5, .anyDescrPhrase([
            "synology", "qnap", "asustor", "terra master", "terramaster",
            "western digital", "buffalo", "drobo"
        ])),
        DeviceRule("nas.mdns.vendor", .nas, 5,
                   .anyMDNS(["_dsm._tcp", "_synology._tcp", "_qnap._tcp", "_adisk._tcp"])),
        DeviceRule("nas.port.nfs", .nas, W.strong, .port(2049)),
        DeviceRule("nas.port.afp", .nas, W.moderate, .port(548)),
        DeviceRule("nas.mdns.share", .nas, W.moderate,
                   .anyMDNS(["_afpovertcp._tcp", "_nfs._tcp", "_smb._tcp"])),
        // 5000 is Synology's web UI — and also macOS AirPlay Receiver, which is why this is
        // guarded rather than taken at face value.
        // Guarded twice, because 5000 is genuinely ambiguous: it is Synology's web UI *and* macOS
        // AirPlay Receiver. The vendor check catches it when the OUI is known; the 7000 check
        // catches it when it is not, since 5000+7000 is AirPlay's pair and no Synology opens 7000.
        DeviceRule("nas.port.dsm", .nas, W.moderate,
                   .all([
                       .anyPort([5000, 5001]),
                       .not(.descrPhrase("apple")),
                       .not(.port(7000))
                   ])),
        DeviceRule("nas.port.stack", .nas, W.moderate,
                   .all([.port(445), .anyPort([548, 2049, 5000, 5001])])),
        // Whole token: "jonas-pc" is not a NAS.
        DeviceRule("nas.host", .nas, W.moderate, .anyHostToken([
            "nas", "synology", "diskstation", "qnap", "truenas", "freenas", "unraid",
            "openmediavault", "omv"
        ])),
        DeviceRule("nas.title", .nas, W.moderate,
                   .anyDescrPhrase(["diskstation", "qts", "truenas", "openmediavault"])),
        DeviceRule("nas.ssdp.mediaserver", .nas, W.weak,
                   .descrPhrase("urn:schemas-upnp-org:device:mediaserver"))
    ]

    // MARK: - Routers / access points

    static let routers: [DeviceRule] = [
        // Being the default gateway is the best router evidence a LAN scan can have.
        DeviceRule("router.gateway", .router, 5, .isGateway),
        DeviceRule("router.gateway.web", .router, W.moderate,
                   .all([.isGateway, .anyPort([80, 443])])),
        DeviceRule("router.vendor", .router, W.moderate, .anyDescrPhrase([
            "huawei", "zte", "tp-link", "tplink", "netgear", "asustek", "d-link", "mikrotik",
            "zyxel", "technicolor", "sagemcom", "arris", "actiontec", "fritz", "avm",
            "turk telekom", "airties"
        ])),
        DeviceRule("router.vendor.enterprise", .router, W.strong,
                   .anyDescrPhrase(["cisco", "juniper", "fortinet", "arista"])),
        DeviceRule("ap.vendor", .accessPoint, W.strong,
                   .anyDescrPhrase(["ubiquiti", "aruba", "ruckus", "meraki", "engenius"])),
        DeviceRule("ap.descr", .accessPoint, W.strong,
                   .anyDescrPhrase(["unifi", "access point", "uap-", "wireless ap"])),
        DeviceRule("router.host", .router, W.moderate, .anyHostToken([
            "router", "gateway", "hgw", "modem", "openwrt", "ddwrt", "pfsense", "opnsense",
            "fritz", "mikrotik", "edgerouter"
        ])),
        DeviceRule("router.ttl255", .router, W.moderate, .ttlNear(255)),
        // SSDP's InternetGatewayDevice is a device declaring itself the way out of the network.
        DeviceRule("router.ssdp.igd", .router, W.strong,
                   .descrPhrase("urn:schemas-upnp-org:device:internetgatewaydevice")),
        DeviceRule("router.snmp", .router, W.moderate, .anyDescrPhrase([
            "ios software", "routeros", "openwrt", "edgeos", "junos", "fortios", "vyos", "fortigate"
        ])),
        // Was a full verdict on its own; a page titled "Login" is the weakest possible hint.
        DeviceRule("router.title", .router, W.hint, .anyDescrPhrase(["login", "router", "gateway"]))
    ]

    // MARK: - Windows / Linux
    //
    // TTL is the OS fingerprint that was collected and never read: 64 Linux/Apple, 128 Windows,
    // 255 network gear. The TCP fallback path reports no TTL, so these simply do not fire for
    // ICMP-blocked hosts — correct, rather than a gap.

    static let windowsLinux: [DeviceRule] = [
        DeviceRule("win.smb.stack", .windows, W.strong, .all([.port(445), .anyPort([135, 139])])),
        DeviceRule("win.port.msrpc", .windows, W.moderate, .port(135)),
        DeviceRule("win.port.rdp", .windows, W.moderate, .port(3389)),
        DeviceRule("win.netbios.workgroup", .windows, W.moderate, .hasWorkgroup),
        DeviceRule("win.ttl128", .windows, W.weak, .ttlNear(128)),
        DeviceRule("win.host", .windows, W.hint,
                   .anyHostToken(["desktop", "laptop", "pc", "win", "workstation"])),
        DeviceRule("win.not.apple", .windows, W.penalty, .descrPhrase("apple")),

        DeviceRule("linux.ttl64.ssh", .linux, W.moderate, .all([
            .ttlNear(64), .port(22), .not(.descrPhrase("apple")), .not(.anyPort([135, 445]))
        ])),
        DeviceRule("linux.snmp", .linux, W.moderate, .descrPhrase("linux ")),
        DeviceRule("linux.host", .linux, W.weak, .anyHostToken([
            "ubuntu", "debian", "raspberrypi", "raspberry", "rpi", "fedora", "centos", "proxmox"
        ])),
        DeviceRule("apple.ttl64", .mac, W.hint, .all([.ttlNear(64), .descrPhrase("apple")]))
    ]

    // MARK: - Cameras

    static let cameras: [DeviceRule] = [
        DeviceRule("cam.port.rtsp", .camera, 5, .port(554)),
        DeviceRule("cam.vendor", .camera, 5, .anyDescrPhrase([
            "hikvision", "dahua", "axis communications", "reolink", "amcrest", "uniview",
            "vivotek", "mobotix", "foscam", "annke", "lorex"
        ])),
        DeviceRule("cam.mdns", .camera, W.strong,
                   .anyMDNS(["_rtsp._tcp", "_onvif._tcp", "_axis-video._tcp"])),
        DeviceRule("cam.descr", .camera, W.strong,
                   .anyDescrPhrase(["onvif", "ipcam", "ip camera", "network camera"])),
        DeviceRule("cam.host", .camera, W.moderate,
                   .anyHostToken(["cam", "camera", "ipcam", "nvr", "doorbell"])),
        DeviceRule("cam.port.stack", .camera, W.moderate,
                   .all([.port(554), .anyPort([80, 8000, 8080])]))
    ]

    // MARK: - IoT

    static let iot: [DeviceRule] = [
        DeviceRule("iot.vendor", .iot, 5, .anyDescrPhrase(iotVendors)),
        DeviceRule("iot.mdns.hap", .iot, 5,
                   .anyMDNS(["_hap._tcp", "_homekit._tcp", "_matter._tcp", "_matterc._udp"])),
        DeviceRule("iot.mdns.hue", .iot, 5, .mdns("_hue._tcp")),
        DeviceRule("iot.descr", .iot, W.strong, .anyDescrPhrase([
            "esp8266", "esp32", "tasmota", "esphome", "shelly", "hue bridge", "tuya", "smartlife"
        ])),
        // A web UI and nothing else — the surface of a thing that does one job.
        DeviceRule("iot.smallsurface", .iot, W.weak, .all([
            .anyPort([80, 8080]),
            .not(.anyPort([22, 445, 3389, 139, 135, 548, 2049]))
        ]))
    ]

    // MARK: - Consoles

    static let consoles: [DeviceRule] = [
        DeviceRule("console.vendor", .gameConsole, W.strong,
                   .anyDescrPhrase(["sony interactive", "nintendo"])),
        DeviceRule("console.host", .gameConsole, W.strong,
                   .anyHostToken(["playstation", "ps4", "ps5", "xbox", "switch", "nintendo"])),
        DeviceRule("console.descr", .gameConsole, W.strong,
                   .anyDescrPhrase(["playstation", "xbox", "nintendo switch"])),
        DeviceRule("console.ssdp", .gameConsole, W.moderate,
                   .anyDescrPhrase(["ps5", "ps4", "xbox one", "xbox series"]))
    ]

    // MARK: - Server
    //
    // Deliberately the weakest rules in the table. "Has port 80 open" is the least informative
    // fact a host can offer — nearly everything with a network stack answers it. As a first-match
    // rule it used to shadow IoT entirely, so every smart bulb with a web UI was a "Server".
    // Reaching the threshold now takes SSH *and* a web port *and* not being an IoT vendor, which
    // is roughly what the word means.

    static let servers: [DeviceRule] = [
        DeviceRule("server.ssh", .server, W.weak, .port(22)),
        DeviceRule("server.http", .server, W.hint, .anyPort([80, 443, 8080])),
        DeviceRule("server.stack", .server, W.moderate, .all([
            .port(22),
            .anyPort([80, 443, 8080]),
            .not(.anyDescrPhrase(iotVendors))
        ])),
        DeviceRule("server.plex", .server, W.moderate, .port(32400))
    ]
}
