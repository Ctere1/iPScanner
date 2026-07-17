import XCTest
@testable import iPScanner

/// The tokenizer exists to make `hostname.contains(...)` unnecessary. These are the strings that
/// motivated it.
final class TokenizerTests: XCTestCase {

    func testSplitsOnPunctuation() {
        XCTAssertEqual(Tokenizer.tokens("Jonas-PC.local"), ["jonas", "pc"])
    }

    /// The whole point: "natview" holds no "tv" token, so no substring can make it a television.
    func testDoesNotInventSubstrings() {
        XCTAssertEqual(Tokenizer.tokens("natview"), ["natview"])
        XCTAssertFalse(Tokenizer.tokens("natview").contains("tv"))
        XCTAssertFalse(Tokenizer.tokens("jonas-pc").contains("nas"))
        XCTAssertFalse(Tokenizer.tokens("atlas-nasa-lab").contains("nas"))
    }

    /// Digit↔letter boundaries split too, or a model number is one opaque token no rule can match.
    func testSplitsDigitLetterBoundaries() {
        XCTAssertEqual(Tokenizer.tokens("HP-LaserJet-M404dn"), ["hp", "laserjet", "m", "404", "dn"])
    }

    func testKeepsOnlyTheLeftmostLabel() {
        // The domain belongs to the network, not the device.
        XCTAssertEqual(Tokenizer.tokens("printer.office.example.com"), ["printer"])
    }

    func testLowercases() {
        XCTAssertEqual(Tokenizer.tokens("Cemils-iPhone"), ["cemils", "iphone"])
    }

    func testHandlesEmptyAndNil() {
        XCTAssertTrue(Tokenizer.tokens(nil).isEmpty)
        XCTAssertTrue(Tokenizer.tokens("").isEmpty)
        XCTAssertTrue(Tokenizer.tokens("...").isEmpty)
    }

    func testUnderscoresAndSpaces() {
        XCTAssertEqual(Tokenizer.tokens("living_room tv"), ["living", "room", "tv"])
    }

    /// A device deliberately named "tv" still matches — the rule is exactness, not avoidance.
    func testExactTokenStillMatches() {
        XCTAssertTrue(Tokenizer.tokens("living-room-tv").contains("tv"))
        XCTAssertTrue(Tokenizer.tokens("office-nas").contains("nas"))
    }
}
