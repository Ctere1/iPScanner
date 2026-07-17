import XCTest
@testable import iPScanner

/// Two invariants that nothing else enforces, and whose failure is silent both ways.
///
/// Half the mDNS rules in this table were dead when these tests were written: they named service
/// types the browser never browsed, so the evidence could not arrive and the rule could not fire.
/// Nothing complained — a rule that never matches looks exactly like a rule for a device you do not
/// own.
@MainActor
final class BonjourServiceTypeTests: XCTestCase {

    private var browsed: Set<String> {
        Set(MDNSDiscovery.serviceTypes.map(\.type))
    }

    /// Every service type a rule names must be one the browser actually looks for.
    func testEveryRuleServiceTypeIsBrowsed() {
        var referenced: Set<String> = []
        for rule in DeviceRules.all {
            referenced.formUnion(Self.serviceTypes(in: rule.matcher))
        }
        let dead = referenced.subtracting(browsed)
        XCTAssertTrue(
            dead.isEmpty,
            "these rules can never fire — the browser does not browse: \(dead.sorted())"
        )
    }

    /// Every type browsed must be declared in NSBonjourServices, or macOS refuses the browse and
    /// the app silently discovers nothing.
    func testBrowsedTypesAreDeclaredInInfoPlist() throws {
        let declared = try Self.declaredBonjourServices()
        let undeclared = browsed.subtracting(declared)
        XCTAssertTrue(
            undeclared.isEmpty,
            "browsed but not in project.yml's NSBonjourServices, so macOS will block them: \(undeclared.sorted())"
        )
    }

    /// And the other direction: a declaration for a type nobody browses is dead weight in the
    /// privacy prompt.
    func testNoStrayDeclarations() throws {
        let declared = try Self.declaredBonjourServices()
        XCTAssertTrue(
            declared.subtracting(browsed).isEmpty,
            "declared but never browsed: \(declared.subtracting(browsed).sorted())"
        )
    }

    func testServiceTypesAreWellFormed() {
        for (type, label) in MDNSDiscovery.serviceTypes {
            XCTAssertTrue(type.hasPrefix("_"), "\(type) must start with an underscore")
            XCTAssertTrue(
                type.hasSuffix("._tcp") || type.hasSuffix("._udp"),
                "\(type) must name a transport"
            )
            XCTAssertFalse(label.isEmpty, "\(type) has no display label")
        }
    }

    func testNoDuplicateServiceTypes() {
        let types = MDNSDiscovery.serviceTypes.map(\.type)
        XCTAssertEqual(Set(types).count, types.count, "a duplicate means two browsers for one type")
    }

    // MARK: - Helpers

    /// Walks a matcher tree for the service types it names.
    private static func serviceTypes(in matcher: Matcher) -> Set<String> {
        switch matcher {
        case .mdns(let type):
            return [type]
        case .anyMDNS(let types):
            return Set(types)
        case .not(let inner):
            return serviceTypes(in: inner)
        case .all(let inner), .any(let inner):
            return inner.reduce(into: Set<String>()) { $0.formUnion(serviceTypes(in: $1)) }
        default:
            return []
        }
    }

    /// Reads NSBonjourServices out of the built app's Info.plist — the thing macOS actually honours,
    /// rather than the project.yml that generates it.
    private static func declaredBonjourServices() throws -> Set<String> {
        guard let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] else {
            throw XCTSkip("NSBonjourServices missing from the host app's Info.plist")
        }
        return Set(services)
    }
}
