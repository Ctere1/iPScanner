import Foundation

/// Scores every rule and takes the best-supported answer.
///
/// The previous classifier was a first-match if-chain, which made rule *order* the real logic: the
/// `.server` test sat above the `.iot` test and matched on port 80, so no IoT device with a web
/// interface could ever be identified — a bug invisible at the site that caused it. Scoring has no
/// order to get wrong. Every rule votes, the weights say how loudly, and adding a rule cannot
/// silently disable another one.
struct DeviceClassifier: Sendable {
    let rules: [DeviceRule]

    /// Below this, say nothing. A lone weak signal is not an identification, and "Server" on the
    /// evidence of one open port is worse than an honest dash.
    static let minimumScore = 3

    static let live = DeviceClassifier(rules: DeviceRules.all)

    init(rules: [DeviceRule]) {
        self.rules = rules
    }

    func classify(_ signals: DeviceSignals) -> DeviceClassification {
        var scores: [DeviceType: Int] = [:]
        var matched: [DeviceType: [String]] = [:]

        for rule in rules where rule.matcher.matches(signals) {
            scores[rule.type, default: 0] += rule.weight
            matched[rule.type, default: []].append(rule.id)
        }

        let eligible = scores.filter { $0.value >= Self.minimumScore }
        // Ties go to the more specific answer: "printer" and "server" both at 4 means printer,
        // because everything serves something.
        guard let best = eligible.max(by: { lhs, rhs in
            (lhs.value, -lhs.key.specificity) < (rhs.value, -rhs.key.specificity)
        }) else {
            return .unknown
        }

        let runnerUp = eligible
            .filter { $0.key != best.key }
            .map(\.value)
            .max() ?? 0

        return DeviceClassification(
            type: best.key,
            confidence: confidence(score: best.value, runnerUp: runnerUp),
            score: best.value,
            matchedRuleIDs: (matched[best.key] ?? []).sorted()
        )
    }

    /// A contested verdict is reported as contested rather than asserted. An Apple host with 631
    /// open really is ambiguous, and saying "Confident" about it would be a lie.
    private func confidence(score: Int, runnerUp: Int) -> DeviceConfidence {
        if score >= 8 && score - runnerUp >= 3 { return .high }
        if score >= 5 { return .medium }
        return .low
    }
}

extension DeviceClassifier {
    /// Convenience for call sites that only have a `Host`.
    ///
    /// Note what this cannot see: a host alone carries no Bonjour data and does not know whether it
    /// is the subnet's gateway. Callers with that context should build `DeviceSignals` themselves.
    static func classify(_ host: Host) -> DeviceType {
        live.classify(DeviceSignals.from(host: host)).type
    }
}
