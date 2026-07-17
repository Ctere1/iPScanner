import Foundation
import Observation

/// Polite check against the GitHub Releases API to see if a newer iPScanner
/// is published. Zero-dependency, no auto-install: when an update is found
/// we surface an alert with a "View Release" button that opens the release
/// page in the user's browser.
@Observable
@MainActor
final class UpdateChecker {
    struct AvailableUpdate: Equatable {
        let currentVersion: String
        let latestVersion: String
        let releaseURL: URL
        let releaseName: String
    }

    private(set) var availableUpdate: AvailableUpdate?
    private(set) var lastError: String?
    private(set) var isChecking: Bool = false

    /// Repository the update check queries, as `owner/name`.
    ///
    /// Read from Info.plist rather than hardcoded so a fork points at its own releases without
    /// patching code — and so this stays a one-line change when rebasing onto upstream. It matters
    /// for correctness, not just tidiness: a fork's build advertising upstream's releases would
    /// walk the user onto a download that does not contain the fork's fixes.
    nonisolated static let defaultRepository = "Ctere1/iPScanner"

    nonisolated static let repository: String = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "iPScannerUpdateRepository") as? String,
              isValidRepository(raw) else { return defaultRepository }
        return raw
    }()

    /// `owner/name`, restricted to the characters GitHub allows. The value is interpolated into a
    /// URL, so anything else could point the check somewhere other than the intended repo.
    nonisolated static func isValidRepository(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(allowed.contains) }
    }

    nonisolated static var releasesAPI: URL? {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// The repository's page and issue form.
    ///
    /// Here rather than at the menu items that open them, because this is the type that knows which
    /// repository this build belongs to and has already validated the string going into the URL.
    /// They were hardcoded to upstream while the update check pointed at the fork — so "Report an
    /// Issue…" filed this fork's bugs on someone else's tracker, and "iPScanner on GitHub" offered
    /// the source of a different app. The reasoning in `defaultRepository` above covers all three;
    /// only the update check was actually following it.
    nonisolated static var repositoryURL: URL? {
        URL(string: "https://github.com/\(repository)")
    }

    nonisolated static var newIssueURL: URL? {
        URL(string: "https://github.com/\(repository)/issues/new")
    }

    static let autoCheckInterval: TimeInterval = 24 * 60 * 60  // 24 hours

    nonisolated static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// Manual trigger: always hits the API.
    func checkForUpdates() async {
        await runCheck()
    }

    /// Auto-check helper. Skips the network round-trip if `lastCheckAt`
    /// is younger than `autoCheckInterval`.
    func autoCheckIfNeeded(lastCheckAt: Date?) async -> Date {
        let now = Date()
        if let last = lastCheckAt, now.timeIntervalSince(last) < Self.autoCheckInterval {
            return last
        }
        await runCheck()
        return now
    }

    func clearAvailableUpdate() {
        availableUpdate = nil
    }

    private func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            let current = Self.currentVersion()
            if Self.isNewer(release.normalizedTag, than: current) {
                availableUpdate = AvailableUpdate(
                    currentVersion: current,
                    latestVersion: release.normalizedTag,
                    releaseURL: release.htmlURL,
                    releaseName: release.name ?? release.tagName
                )
            } else {
                availableUpdate = nil
            }
            lastError = nil
        } catch UpdateError.noReleases {
            // Nothing published to be behind of, so this reads as "up to date" rather than an error.
            availableUpdate = nil
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Version comparison

    /// Semver-ish comparison. Strips a leading `v`, splits on dots, compares
    /// numerically component-by-component. Trailing zeros count as equal
    /// (`1.2.0` == `1.2`).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = parseVersion(candidate)
        let rhs = parseVersion(current)
        let length = max(lhs.count, rhs.count)
        for i in 0..<length {
            let a = i < lhs.count ? lhs[i] : 0
            let b = i < rhs.count ? rhs[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated static func parseVersion(_ raw: String) -> [Int] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Drop pre-release / build metadata after `-` or `+`
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<cut])
        }
        return s.split(separator: ".").compactMap { Int($0) }
    }

    // MARK: - GitHub API

    struct Release: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL

        var normalizedTag: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }

    enum UpdateError: Error, LocalizedError {
        case invalidResponse
        case decodingFailed
        case untrustedReleaseURL
        case misconfiguredRepository
        /// The repository exists but has published nothing yet — not a failure.
        case noReleases

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub Releases API did not return a successful response."
            case .decodingFailed: "Could not decode the release payload."
            case .untrustedReleaseURL: "The release payload pointed somewhere other than github.com."
            case .misconfiguredRepository: "The configured update repository is not a valid owner/name."
            case .noReleases: "No releases have been published yet."
            }
        }
    }

    /// `html_url` arrives from the network and is handed to LaunchServices when the user clicks
    /// "View Release" — which will launch a local app bundle for a `file://` URL just as readily
    /// as it opens a web page. Anything but an https github.com link is rejected.
    nonisolated static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com"
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = Self.releasesAPI else { throw UpdateError.misconfiguredRepository }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iPScanner-update-check", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        // A repo with no releases answers 404. That is the expected state for a fresh fork, not a
        // failure worth showing the user as one.
        if http.statusCode == 404 { throw UpdateError.noReleases }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw UpdateError.decodingFailed
        }
        guard Self.isTrustedReleaseURL(release.htmlURL) else {
            throw UpdateError.untrustedReleaseURL
        }
        return release
    }
}
