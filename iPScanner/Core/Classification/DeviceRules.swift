import Foundation

/// The evidence table. Data, not control flow — the engine in DeviceClassifier scores it.
enum DeviceRules {
    /// Vendors that make small connected things. Referenced by the server rule too, to keep a
    /// light bulb with a web UI from being called a server.
    ///
    /// Every entry here has to pass one test: does the company make *only* this kind of thing? A
    /// name is evidence only if it is unambiguous. That test is why "samsung" is not in the TV list
    /// (phones, SSDs, fridges), why "philips" is qualified to "philips lighting" (they also make
    /// televisions), and why bare "hewlett" is gone from the printer list (HPE makes access
    /// points). Each of those was a real misidentification before it was a rule.
    static let iotVendors = [
        // Modules and smart-home platforms
        "espressif", "tuya", "sonoff", "itead", "shelly", "allterco", "xiaomi", "yeelight",
        "signify", "philips lighting", "nest labs", "amazon technologies", "wyze",
        "ikea of sweden", "aqara", "lumi", "broadlink", "ecobee", "wemo", "belkin",
        "nanoleaf", "govee", "meross", "sensibo", "netatmo", "tado",
        // Connected white goods. BSH is Bosch/Siemens — the Home Connect ovens, dishwashers and
        // fridges. Named rather than "bosch", which also makes industrial and automotive gear.
        "bsh hausger", "miele", "electrolux", "candy hoover",
        // Robot vacuums
        "roborock", "ecovacs", "dreame", "irobot"
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
        // "hewlett" is qualified, not bare. HP Inc. and Hewlett Packard Enterprise have been two
        // different companies since 2015: HP Inc. makes the printers, HPE makes servers and
        // networking — Aruba is theirs. A bare substring match calls an HPE access point a printer,
        // which is exactly what it did on a real network.
        DeviceRule("printer.vendor", .printer, W.strong, .all([
            .anyDescrPhrase([
                "hewlett", "hp inc", "brother", "canon", "seiko epson", "epson", "lexmark",
                "xerox", "ricoh", "kyocera", "oki ", "konica", "zebra", "dymo"
            ]),
            .not(.descrPhrase("hewlett packard enterprise"))
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
        //
        // Nothing here scores AirPlay for .appleTV, and that is the whole point.
        //
        // `_airplay._tcp`, `_raop._tcp`, port 7000 and port 5000 all mean the same thing: an
        // AirPlay receiver is listening. That is true of an Apple TV, of a HomePod, and of any Mac
        // with AirPlay Receiver switched on — which is the default on a modern macOS. So none of
        // them can name the device, and every attempt to make them has been wrong on a real
        // network: first the 5000+7000 port pair, then `_airplay._tcp` itself, each time turning a
        // MacBook Pro into an Apple TV.
        //
        // An Apple TV is identified by what only an Apple TV says: `model=AppleTV*` in
        // `_device-info._tcp`, or its own name. The cost is that an Apple TV which publishes no
        // device-info reads as a Mac or as unknown — which is the right trade, because the
        // alternative mislabels every Mac in the building.
        DeviceRule("apple.host.appletv", .appleTV, W.strong,
                   .anyHostToken(["appletv", "apple-tv", "atv"])),
        // AirPlay audio. Same ambiguity: a HomePod publishes it, and so does a Mac. A hint only,
        // so it can corroborate a speaker vendor without naming one on its own.
        DeviceRule("raop.mdns", .speaker, W.hint, .mdns("_raop._tcp")),
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
        // 5, matching nas.vendor: these companies make networking gear and nothing else, which is
        // as specific a statement as "Synology". At W.strong they lost to the server rules below,
        // and a UniFi AP — SSH and a web UI, like every AP — came back as "Server".
        DeviceRule("ap.vendor", .accessPoint, 5,
                   .anyDescrPhrase([
                       "ubiquiti", "aruba", "ruckus", "meraki", "engenius",
                       // HPE owns Aruba, and its OUIs register under the parent name.
                       "hewlett packard enterprise"
                   ])),
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
    // Deliberately the weakest rules in the table, and they were still too strong.
    //
    // The principle they kept getting wrong: SSH and a web UI describe how a device is
    // *administered*, not what it is. Every access point, router, NAS and firewall has both. So
    // "server" evidence must never outrank a specific identification — as a first-match rule it
    // shadowed IoT entirely (every smart bulb with a web UI was a "Server"), and even after being
    // demoted to weights it still totalled 6 and beat a named AP vendor at 4, so a UniFi AP came
    // back as "Server" on a real network.
    //
    // SSH + a web port now totals 4: enough to clear the threshold and name an actual server, not
    // enough to outvote anything that knows what it is looking at.

    static let servers: [DeviceRule] = [
        DeviceRule("server.ssh", .server, W.hint, .port(22)),
        DeviceRule("server.http", .server, W.hint, .anyPort([80, 443, 8080])),
        DeviceRule("server.stack", .server, W.weak, .all([
            .port(22),
            .anyPort([80, 443, 8080]),
            .not(.anyDescrPhrase(iotVendors))
        ])),
        // Plex is a real identification rather than an administration surface, so it keeps its
        // weight: nothing else answers on 32400.
        DeviceRule("server.plex", .server, W.moderate, .port(32400))
    ]
}
