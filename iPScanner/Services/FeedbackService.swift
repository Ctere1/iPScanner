import Foundation

struct FeedbackService {
    static let endpoint = URL(string: "https://ipscanner-feedback-relay.ck-7fa.workers.dev/feedback")!
    struct Receipt: Decodable { let issueNumber: Int; let issueURL: URL }
    struct Failure: Decodable { let error: String }
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func send(_ draft: FeedbackDraft, environment: String, session: URLSession = .shared) async throws -> Receipt {
        let report = draft.body(environment: environment)
        guard draft.isValid, draft.title.utf16.count <= 200, report.utf16.count <= 10000 else {
            throw ServiceError(message: "Use a title up to 200 characters and a report up to 10,000 characters.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": draft.title, "body": report, "type": draft.kind == .bug ? "bug" : "feature"])
        guard (request.httpBody?.count ?? 0) <= 32768 else { throw ServiceError(message: "This report is too large. Shorten it before sending.") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError(message: "No response from the feedback service.") }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError(message: (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "Could not deliver your report. Please try later.")
        }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.issueNumber > 0, receipt.issueURL.absoluteString == "https://github.com/canberkys/iPScanner/issues/\(receipt.issueNumber)" else {
            throw ServiceError(message: "Delivery could not be confirmed. Check the issue list before retrying.")
        }
        return receipt
    }
}
