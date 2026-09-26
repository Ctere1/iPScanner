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
}


private final class UpdateResponseProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class UpdateResponseTests: XCTestCase {
    func testSuccessfulCheckFailureRecoveryAndDailyThrottle() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let checker = UpdateChecker(session: session)
        UpdateResponseProtocol.calls = 0
        UpdateResponseProtocol.status = 200
        UpdateResponseProtocol.body = Data(#"{"tag_name":"v99.0.0","html_url":"https://github.com/canberkys/iPScanner/releases/tag/v99.0.0"}"#.utf8)
        await checker.checkForUpdates()
        XCTAssertEqual(checker.availableUpdate?.latestVersion, "99.0.0")
        XCTAssertNil(checker.lastError)
        _ = await checker.autoCheckIfNeeded(lastCheckAt: Date())
        XCTAssertEqual(UpdateResponseProtocol.calls, 1)
        UpdateResponseProtocol.status = 503
        await checker.checkForUpdates()
        XCTAssertNotNil(checker.lastError)
        XCTAssertFalse(checker.isChecking)
        UpdateResponseProtocol.status = 200
        UpdateResponseProtocol.body = Data("invalid JSON".utf8)
        await checker.checkForUpdates()
        XCTAssertEqual(checker.lastError, "Could not decode the release payload.")
        UpdateResponseProtocol.body = Data(#"{"tag_name":"v0.0.0","html_url":"https://github.com/canberkys/iPScanner/releases/tag/v0.0.0"}"#.utf8)
        await checker.checkForUpdates()
        XCTAssertNil(checker.availableUpdate)
        XCTAssertNil(checker.lastError)
    }
}
