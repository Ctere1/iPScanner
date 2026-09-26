import XCTest
@testable import iPScanner

final class OUILookupTests: XCTestCase {

    func testRegistryParsersIgnoreAddressLinesAndKeepVendorPunctuation() {
        let input = """
        28-6f-b9   (hex)      Example, Inc. (Research)
        286FB9     (base 16)  Example, Inc. (Research)
            123 Example Street
        invalid (hex) Bad Vendor
        """
        XCTAssertEqual(OUILookup.parseMAL(content: input), ["286FB9": "Example, Inc. (Research)"])
    }

    func testSubBlockParsersKeepDistinctAssignmentsUnderSameOUI() {
        let input = """
        C8-5C-E2 (hex) First
        700000-7FFFFF (base 16) First
        C8-5C-E2 (hex) Second
        A00000-AFFFFF (base 16) Second
        """
        XCTAssertEqual(OUILookup.parseSubBlock(content: input, subPrefixHexLength: 1),
                       ["C85CE27": "First", "C85CE2A": "Second"])
        XCTAssertEqual(OUILookup.parseSubBlock(content: input, subPrefixHexLength: 3),
                       ["C85CE2700": "First", "C85CE2A00": "Second"])
    }

    func testMalformedHeaderCannotReusePreviousOUI() {
        let input = """
        C8-5C-E2 (hex) Good
        NOT-OUI (hex) Bad
        A00000-AFFFFF (base 16) Bad
        """
        XCTAssertTrue(OUILookup.parseSubBlock(content: input, subPrefixHexLength: 1).isEmpty)
    }

    // MARK: - normalizedHex

    func testNormalizedHexUppercases() {
        XCTAssertEqual(OUILookup.normalizedHex("a8:bb:cc:dd:ee:ff"), "A8BBCCDDEEFF")
    }

    func testNormalizedHexPadsSingleDigitSegments() {
        // arp -an output sometimes drops leading zeros: "0:1:2:3:4:5" → "000102030405"
        XCTAssertEqual(OUILookup.normalizedHex("0:1:2:3:4:5"), "000102030405")
    }

    func testNormalizedHexHandlesMixedCase() {
        XCTAssertEqual(OUILookup.normalizedHex("a8:Bb:cC:Dd:eE:Ff"), "A8BBCCDDEEFF")
    }

    func testNormalizedHexReturnsEmptyForShortInput() {
        XCTAssertEqual(OUILookup.normalizedHex("a8:bb:cc"), "")
    }

    // MARK: - 3-tier priority

    func testMASOverridesMAMAndMAL() {
        // Same OUI 12-34-56, MA-S sub-block FFA, MA-M sub-block F, MA-L base.
        let lookup = OUILookup(
            mas: ["103456FFA": "Specific MA-S Vendor"],
            mam: ["1034567": "MA-M Vendor"],
            mal: ["103456": "MA-L Vendor"]
        )
        // MAC where bits 25-36 = FFAxx → must hit MA-S key 103456FFA.
        XCTAssertEqual(lookup.vendor(forMAC: "10:34:56:FF:A1:23"), "Specific MA-S Vendor")
    }

    func testMAMOverridesMAL() {
        let lookup = OUILookup(
            mas: ["103456FFA": "MA-S Vendor"],
            mam: ["1034568": "MA-M Vendor"],
            mal: ["103456": "MA-L Vendor"]
        )
        // MAC bits 25-28 = 8 (sub-prefix length 1) → matches MA-M but not MA-S.
        XCTAssertEqual(lookup.vendor(forMAC: "10:34:56:8A:BC:DE"), "MA-M Vendor")
    }

    func testMALFallbackWhenNoSubBlock() {
        let lookup = OUILookup(
            mas: [:],
            mam: [:],
            mal: ["A8BBCC": "Cisco Systems"]
        )
        XCTAssertEqual(lookup.vendor(forMAC: "A8:BB:CC:11:22:33"), "Cisco Systems")
    }

    func testReturnsNilWhenNotInAnyRegistry() {
        let lookup = OUILookup(mas: [:], mam: [:], mal: [:])
        XCTAssertNil(lookup.vendor(forMAC: "A8:BB:CC:DD:EE:FF"))
    }

    func testLookupIsCaseInsensitive() {
        let lookup = OUILookup(
            mas: [:],
            mam: [:],
            mal: ["A8BBCC": "Vendor"]
        )
        XCTAssertEqual(lookup.vendor(forMAC: "a8:bb:cc:dd:ee:ff"), "Vendor")
    }

    func testLookupHandlesShortMAC() {
        // MAC with only OUI portion → falls through to MA-L only.
        let lookup = OUILookup(
            mas: ["A8BBCCDDE": "Should not match"],
            mam: ["A8BBCCD": "Should not match"],
            mal: ["A8BBCC": "MA-L Hit"]
        )
        // Just 3 segments → normalizedHex returns "" → empty count < 9 → uses prefix(6) of "" → no match
        XCTAssertNil(lookup.vendor(forMAC: "A8:BB:CC"))
    }
}
