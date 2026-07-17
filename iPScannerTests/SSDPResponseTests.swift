import XCTest
@testable import iPScanner

/// SSDP's wire format is fixed, so every case worth covering is a byte array rather than a device
/// someone has to own.
final class SSDPResponseTests: XCTestCase {

    // MARK: - Request

    func testSearchRequestIsAWellFormedMSEARCH() {
        let data = SSDPResponse.searchRequest(host: "10.0.0.1")
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("HOST: 10.0.0.1:1900\r\n"), "unicast: addressed to the host itself")
        XCTAssertTrue(text.contains("MAN: \"ssdp:discover\"\r\n"), "MAN must be quoted per the spec")
        XCTAssertTrue(text.contains("ST: ssdp:all\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"), "headers end with a blank line")
    }

    func testSearchRequestUsesCRLFThroughout() {
        let text = String(decoding: SSDPResponse.searchRequest(host: "10.0.0.1"), as: UTF8.self)
        XCTAssertFalse(text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    // MARK: - Replies

    private func parse(_ text: String) -> SSDPResult? {
        SSDPResponse.parse(Data(text.utf8))
    }

    /// A real Sonos reply.
    func testParsesASonosReply() {
        let result = parse("""
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age = 1800\r
        EXT:\r
        LOCATION: http://10.0.0.42:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/70.3-35220\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:RINCON_48A6B8::urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r
        """)
        XCTAssertEqual(result?.server, "Linux UPnP/1.0 Sonos/70.3-35220")
        XCTAssertEqual(result?.searchTarget, "urn:schemas-upnp-org:device:ZonePlayer:1")
        XCTAssertEqual(result?.location, URL(string: "http://10.0.0.42:1400/xml/device_description.xml"))
        XCTAssertTrue(result?.usn?.hasPrefix("uuid:RINCON") ?? false)
    }

    /// A router announcing itself as the way out — the strongest SSDP router signal.
    func testParsesAnInternetGatewayDevice() {
        let result = parse("""
        HTTP/1.1 200 OK\r
        LOCATION: http://10.0.8.1:5000/rootDesc.xml\r
        SERVER: FortiOS/7.2 UPnP/1.0 miniupnpd/2.1\r
        ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r
        \r
        """)
        XCTAssertEqual(result?.searchTarget, "urn:schemas-upnp-org:device:InternetGatewayDevice:1")
        XCTAssertTrue(result?.server?.contains("FortiOS") ?? false)
    }

    /// Header names are case-insensitive, and devices genuinely disagree about the casing.
    func testHeaderNamesAreCaseInsensitive() {
        let result = parse("HTTP/1.1 200 OK\r\nserver: Test/1.0\r\nSt: upnp:rootdevice\r\n\r\n")
        XCTAssertEqual(result?.server, "Test/1.0")
        XCTAssertEqual(result?.searchTarget, "upnp:rootdevice")
    }

    /// A NOTIFY is unsolicited, carries the same facts, and names them NT rather than ST.
    func testParsesANotifyUsingNTForTheSearchTarget() {
        let result = parse("""
        NOTIFY * HTTP/1.1\r
        NT: urn:schemas-upnp-org:device:MediaRenderer:1\r
        SERVER: Chromecast/1.0\r
        \r
        """)
        XCTAssertEqual(result?.searchTarget, "urn:schemas-upnp-org:device:MediaRenderer:1")
    }

    /// Not every device sends CRLF.
    func testToleratesBareNewlines() {
        let result = parse("HTTP/1.1 200 OK\nSERVER: Test/1.0\nST: upnp:rootdevice\n\n")
        XCTAssertEqual(result?.server, "Test/1.0")
    }

    func testDuplicateHeadersTakeTheFirst() {
        let result = parse("HTTP/1.1 200 OK\r\nSERVER: First\r\nSERVER: Second\r\n\r\n")
        XCTAssertEqual(result?.server, "First")
    }

    func testMalformedLocationIsDroppedNotFatal() {
        let result = parse("HTTP/1.1 200 OK\r\nSERVER: Test/1.0\r\nLOCATION: :::not a url\r\n\r\n")
        XCTAssertEqual(result?.server, "Test/1.0", "one bad header must not lose the rest")
    }

    // MARK: - Refusals

    func testGarbageIsNil() {
        XCTAssertNil(SSDPResponse.parse(Data([0xFF, 0x00, 0xAB, 0xCD])))
        XCTAssertNil(parse("hello"))
        XCTAssertNil(parse(""))
    }

    /// Shaped like SSDP but says nothing: no reason to report a result.
    func testReplyWithNoUsefulHeadersIsNil() {
        XCTAssertNil(parse("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\n\r\n"))
    }

    func testTruncatedPacketDoesNotCrash() {
        XCTAssertNoThrow(parse("HTTP/1.1 200 OK\r\nSER"))
    }
}
