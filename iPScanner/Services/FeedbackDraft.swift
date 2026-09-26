import Foundation

struct FeedbackDraft {
    enum Kind: String, CaseIterable { case bug = "Bug Report", feature = "Feature Request" }
    var kind: Kind = .bug
    var title = ""
    var details = ""
    var steps = ""
    var expected = ""
    var includeEnvironment = true

    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func body(environment: String) -> String {
        var sections = ["## \(kind.rawValue)\n\(details)"]
        if kind == .bug {
            sections += ["## Steps to reproduce\n\(steps)", "## Expected result\n\(expected)"]
        }
        if includeEnvironment { sections.append("## Environment\n\(environment)") }
        return sections.joined(separator: "\n\n")
    }

    func issueURL(environment: String) -> URL? {
        guard isValid else { return nil }
        var url = URLComponents(string: "https://github.com/canberkys/iPScanner/issues/new")!
        url.queryItems = [URLQueryItem(name: "title", value: "[\(kind.rawValue)] \(title)"), URLQueryItem(name: "body", value: body(environment: environment))]
        // Large drafts remain available through Copy Report, without truncated URLs.
        guard let result = url.url, result.absoluteString.utf8.count <= 7500 else { return nil }
        return result
    }

    static var environment: String {
        #if arch(arm64)
        let architecture = "Apple Silicon (arm64)"
        #else
        let architecture = "Intel (x86_64)"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        return "iPScanner: \(version)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nArchitecture: \(architecture)"
    }
}
