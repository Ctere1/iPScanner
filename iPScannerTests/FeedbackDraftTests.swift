import XCTest
@testable import iPScanner

final class FeedbackDraftTests: XCTestCase {
    func testEnvironmentIsOptionalAndTextSurvivesURLEncoding() throws {
        var draft = FeedbackDraft()
        draft.title = "Scan & café?"
        draft.details = "First line\nSecond #line & 100%"
        draft.includeEnvironment = false
        let url = try XCTUnwrap(draft.issueURL(environment: "PRIVATE ENV"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "title" }?.value, "[Bug Report] Scan & café?")
        let body = try XCTUnwrap(query.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains(draft.details))
        XCTAssertFalse(body.contains("PRIVATE ENV"))
    }
    func testEmptyAndOversizedDraftsDoNotGenerateLinks() {
        var draft = FeedbackDraft()
        XCTAssertNil(draft.issueURL(environment: ""))
        draft.title = "Problem"
        draft.details = String(repeating: "a", count: 8000)
        XCTAssertTrue(draft.isValid)
        XCTAssertNil(draft.issueURL(environment: ""))
        XCTAssertTrue(draft.body(environment: "").contains(draft.details))
    }
    func testFeatureRequestOmitsBugSpecificFields() {
        var draft = FeedbackDraft()
        draft.kind = .feature
        draft.details = "Add a feature"
        XCTAssertFalse(draft.body(environment: "macOS").contains("Steps to reproduce"))
        XCTAssertTrue(draft.body(environment: "macOS").contains("macOS"))
    }
}
