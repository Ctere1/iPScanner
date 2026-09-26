import XCTest
@testable import iPScanner

private final class FeedbackURLProtocol: URLProtocol {
    static var responseStatus = 200
    static var responseBody = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class FeedbackServiceTests: XCTestCase {
    private func send(status: Int, response: String) async throws -> FeedbackService.Receipt {
        FeedbackURLProtocol.responseStatus = status
        FeedbackURLProtocol.responseBody = Data(response.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedbackURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var draft = FeedbackDraft(); draft.title = "Test"; draft.details = "Test report"
        return try await FeedbackService.send(draft, environment: "test", session: session)
    }
    func testConfirmedReceipt() async throws {
        let receipt = try await send(status: 200, response: #"{"issueNumber":42,"issueURL":"https://github.com/canberkys/iPScanner/issues/42"}"#)
        XCTAssertEqual(receipt.issueNumber, 42)
    }
    func testRejectsUnexpectedReceiptDestination() async {
        do { _ = try await send(status: 200, response: #"{"issueNumber":42,"issueURL":"https://example.org/issues/42"}"#); XCTFail("Must reject unexpected URL") }
        catch { XCTAssertTrue(error.localizedDescription.contains("could not be confirmed")) }
    }
    func testUnavailableServiceDoesNotReportSuccess() async {
        do { _ = try await send(status: 503, response: #"{"error":"Temporarily unavailable"}"#); XCTFail("Must surface failure") }
        catch { XCTAssertEqual(error.localizedDescription, "Temporarily unavailable") }
    }
}
