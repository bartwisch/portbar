import XCTest
@testable import ServerBar

final class ServerScannerTests: XCTestCase {
    func testParsesAndDeduplicatesListeningPorts() {
        let output = """
        p11196
        cnode
        f14
        tIPv4
        n*:8080
        f15
        tIPv6
        n*:8080
        p68333
        cGoogle Drive
        f30
        tIPv6
        n[::1]:7679
        """

        let servers = ServerScanner.parseLsofOutput(output)

        XCTAssertEqual(servers.count, 2)
        XCTAssertEqual(servers.first?.processName, "Google Drive")
        XCTAssertEqual(servers.first?.port, 7679)
        XCTAssertEqual(servers.last?.processName, "node")
        XCTAssertEqual(servers.last?.port, 8080)
        XCTAssertEqual(servers.last?.boundHosts, ["localhost"])
    }

    func testRecognizesCommonDevelopmentServers() {
        let node = ServerProcess(pid: 10, processName: "node", port: 3000, boundHosts: ["localhost"], openHost: "localhost", workingDirectory: nil, projectName: nil)
        let system = ServerProcess(pid: 11, processName: "ControlCenter", port: 5000, boundHosts: ["localhost"], openHost: "localhost", workingDirectory: nil, projectName: nil)

        XCTAssertTrue(node.isLikelyDevelopmentServer)
        XCTAssertFalse(system.isLikelyDevelopmentServer)
    }

    func testParsesWorkingDirectories() {
        let output = """
        p123
        fcwd
        n/Users/christoph/projects/example
        p456
        fcwd
        n/
        """

        let cwdByPID = ServerScanner.parseCwdOutput(output)

        XCTAssertEqual(cwdByPID[123], "/Users/christoph/projects/example")
        XCTAssertEqual(cwdByPID[456], "/")
    }
}
