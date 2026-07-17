import XCTest
@testable import iPScanner

final class NetworkInterfaceGatewayTests: XCTestCase {
    /// Compared against the machine's real routing table rather than a fixture: the point of the
    /// sysctl walk is that it agrees with what the system actually thinks, and a fixture could not
    /// tell us that.
    func testGatewayMatchesTheSystemRoutingTable() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "netstat -rn -f inet | awk '$1==\"default\"{print $2; exit}'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let expected = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process.waitUntilExit()

        let actual = NetworkInterface.defaultGateway()

        if expected.isEmpty {
            XCTAssertNil(actual, "no default route, so there is no gateway to report")
        } else {
            XCTAssertEqual(actual, expected)
        }
    }

    func testGatewayIsAValidIPv4Address() throws {
        guard let gateway = NetworkInterface.defaultGateway() else {
            throw XCTSkip("this machine has no default route")
        }
        XCTAssertNotNil(IPv4.uint32(from: gateway))
        XCTAssertNotEqual(gateway, "0.0.0.0", "0.0.0.0 is the destination, not the gateway")
    }
}
