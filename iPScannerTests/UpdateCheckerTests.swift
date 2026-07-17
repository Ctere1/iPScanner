import XCTest
@testable import iPScanner

final class UpdateCheckerTests: XCTestCase {

    // MARK: - parseVersion

    func testParseStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.parseVersion("v1.2.0"), [1, 2, 0])
        XCTAssertEqual(UpdateChecker.parseVersion("V1.2.0"), [1, 2, 0])
    }

    func testParseHandlesPlainSemver() {
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.3"), [1, 2, 3])
    }

    func testParseDropsPreReleaseSuffix() {
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.0-beta.1"), [1, 2, 0])
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.0+build.42"), [1, 2, 0])
    }

    func testParseTrimsWhitespace() {
        XCTAssertEqual(UpdateChecker.parseVersion("  1.0.0  "), [1, 0, 0])
    }

    // MARK: - isNewer

    func testIsNewerStrict() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.99"), "should compare numerically, not lexically")
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2.0"))
    }

    func testTrailingZeroIsEqual() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3", than: "1.2.4"))
    }

    func testHandlesVPrefixOnEitherSide() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.2.0", than: "1.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "v1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.0", than: "v1.0.0"))
    }

    // MARK: - Repository configuration

    func testAcceptsWellFormedRepository() {
        for repo in ["Ctere1/iPScanner", "canberkys/iPScanner", "a/b", "org.name/repo-name_1.2"] {
            XCTAssertTrue(UpdateChecker.isValidRepository(repo), "should accept \(repo)")
        }
    }

    /// The value is interpolated into the API URL, so anything that could redirect the check
    /// elsewhere — a path escape, an embedded host, a query — must be rejected.
    func testRejectsMalformedRepository() {
        let bad = [
            "",
            "noslash",
            "too/many/parts",
            "/leading",
            "trailing/",
            "owner/repo?x=1",
            "owner/repo#frag",
            "../../evil",
            "evil.com/a/b",
            "owner /repo",
            "owner/repo/../../other"
        ]
        for repo in bad {
            XCTAssertFalse(UpdateChecker.isValidRepository(repo), "should reject \(repo.debugDescription)")
        }
    }

    /// The bundle under test has no override, so the default must stand on its own.
    func testDefaultRepositoryIsThisFork() {
        XCTAssertTrue(UpdateChecker.isValidRepository(UpdateChecker.defaultRepository))
        XCTAssertEqual(UpdateChecker.defaultRepository, "Ctere1/iPScanner")
    }

    func testReleasesAPIPointsAtConfiguredRepository() throws {
        let url = try XCTUnwrap(UpdateChecker.releasesAPI)
        XCTAssertEqual(url.host, "api.github.com")
        XCTAssertEqual(url.path, "/repos/\(UpdateChecker.repository)/releases/latest")
    }

    // MARK: - Release URL validation

    func testAcceptsGitHubReleaseURL() {
        let url = URL(string: "https://github.com/canberkys/iPScanner/releases/tag/v1.2.1")!
        XCTAssertTrue(UpdateChecker.isTrustedReleaseURL(url))
    }

    /// `html_url` is attacker-controlled if the API response is forged. LaunchServices will launch
    /// a local app bundle for a file:// URL as readily as it opens a web page.
    func testRejectsNonGitHubOrNonHTTPSReleaseURL() {
        let hostile = [
            "file:///Applications/Malware.app",
            "http://github.com/canberkys/iPScanner/releases",
            "https://github.com.evil.example/canberkys/iPScanner",
            "https://evil.example/releases",
            "javascript:alert(1)"
        ]
        for raw in hostile {
            let url = URL(string: raw)!
            XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(url), "should reject \(raw)")
        }
    }
}
