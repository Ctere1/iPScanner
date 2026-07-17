import XCTest
@testable import iPScanner

final class UPnPDescriptionTests: XCTestCase {

    private func parse(_ xml: String) -> UPnPDescription? {
        UPnPDescription.parse(Data(xml.utf8))
    }

    func testParsesASonosDescription() {
        let result = parse("""
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
            <friendlyName>Living Room</friendlyName>
            <manufacturer>Sonos, Inc.</manufacturer>
            <modelNumber>S13</modelNumber>
            <modelName>Sonos One</modelName>
          </device>
        </root>
        """)
        XCTAssertEqual(result?.friendlyName, "Living Room")
        XCTAssertEqual(result?.manufacturer, "Sonos, Inc.")
        XCTAssertEqual(result?.modelName, "Sonos One")
        XCTAssertEqual(result?.modelNumber, "S13")
        XCTAssertEqual(result?.deviceType, "urn:schemas-upnp-org:device:ZonePlayer:1")
    }

    /// A description can nest child devices, each with its own friendlyName. The root device is the
    /// one being asked about, so the first of each field wins.
    func testNestedDevicesDoNotOverrideTheRoot() {
        let result = parse("""
        <root>
          <device>
            <friendlyName>Router</friendlyName>
            <manufacturer>Fortinet</manufacturer>
            <deviceList>
              <device>
                <friendlyName>WANDevice</friendlyName>
                <manufacturer>Someone Else</manufacturer>
              </device>
            </deviceList>
          </device>
        </root>
        """)
        XCTAssertEqual(result?.friendlyName, "Router", "the root device names the host")
        XCTAssertEqual(result?.manufacturer, "Fortinet")
    }

    func testElementNamesAreCaseInsensitive() {
        let result = parse("<root><device><FriendlyName>Test</FriendlyName></device></root>")
        XCTAssertEqual(result?.friendlyName, "Test")
    }

    func testWhitespaceIsTrimmed() {
        let result = parse("<root><device><friendlyName>\n   Kitchen Display  \n</friendlyName></device></root>")
        XCTAssertEqual(result?.friendlyName, "Kitchen Display")
    }

    func testEmptyElementsAreIgnored() {
        let result = parse("<root><device><friendlyName></friendlyName><manufacturer>ACME</manufacturer></device></root>")
        XCTAssertNil(result?.friendlyName)
        XCTAssertEqual(result?.manufacturer, "ACME")
    }

    func testDescriptionTextPoolsEverythingForPhraseMatching() {
        let result = parse("""
        <root><device>
          <friendlyName>Living Room</friendlyName>
          <manufacturer>Sonos, Inc.</manufacturer>
          <modelName>PLAY:1</modelName>
        </device></root>
        """)
        let text = result?.descriptionText ?? ""
        XCTAssertTrue(text.contains("sonos"))
        XCTAssertTrue(text.contains("play:1"))
        XCTAssertEqual(text, text.lowercased(), "pooled text is lowercase, as the matchers expect")
    }

    // MARK: - Refusals

    func testMalformedXMLIsNil() {
        XCTAssertNil(parse("<root><device><friendlyName>Unclosed"))
        XCTAssertNil(parse("not xml at all"))
        XCTAssertNil(UPnPDescription.parse(Data()))
    }

    /// Well-formed but says nothing we asked about.
    func testXMLWithNoInterestingFieldsIsNil() {
        XCTAssertNil(parse("<root><specVersion><major>1</major></specVersion></root>"))
    }
}
