import Foundation

struct ServerProcess: Identifiable, Hashable, Sendable {
    let pid: pid_t
    let processName: String
    let port: Int
    let boundHosts: [String]
    let openHost: String
    let workingDirectory: String?
    let projectName: String?

    var id: String {
        "\(pid)-\(port)"
    }

    var urlString: String {
        "\(scheme)://\(openHost):\(port)"
    }

    var openURL: URL? {
        URL(string: urlString)
    }

    var hostSummary: String {
        boundHosts.joined(separator: ", ")
    }

    var displayName: String {
        projectName ?? processName
    }

    var detailSummary: String {
        var parts = ["\(processName)", "PID \(pid)", hostSummary]

        if let workingDirectory {
            parts.append(workingDirectory)
        }

        return parts.joined(separator: " • ")
    }

    var isLikelyDevelopmentServer: Bool {
        let command = processName.lowercased()

        if Self.excludedCommands.contains(command) {
            return false
        }

        if Self.knownDevelopmentCommands.contains(where: { command == $0 || command.hasPrefix("\($0)-") }) {
            return true
        }

        return port >= 1024 && port < 10000
    }

    var urlOptions: [ServerURL] {
        var hosts = [openHost]

        for host in boundHosts where host != openHost {
            hosts.append(host)
        }

        if !hosts.contains("127.0.0.1") {
            hosts.append("127.0.0.1")
        }

        return hosts
            .filter { !$0.isEmpty }
            .uniqued()
            .map { host in
                ServerURL(host: host, port: port, scheme: scheme)
            }
    }

    private var scheme: String {
        Self.httpsPorts.contains(port) ? "https" : "http"
    }

    private static let httpsPorts: Set<Int> = [443, 8443, 9443]

    private static let knownDevelopmentCommands: Set<String> = [
        "air",
        "bun",
        "cargo",
        "deno",
        "dotnet",
        "go",
        "java",
        "node",
        "php",
        "python",
        "python3",
        "rails",
        "ruby",
        "uvicorn",
        "vite"
    ]

    private static let excludedCommands: Set<String> = [
        "airplayxpchelper",
        "controlcenter",
        "google drive",
        "rapportd",
        "sharingd"
    ]
}

struct ServerURL: Identifiable, Hashable, Sendable {
    let host: String
    let port: Int
    let scheme: String

    var id: String {
        urlString
    }

    var urlString: String {
        "\(scheme)://\(host):\(port)"
    }

    var url: URL? {
        URL(string: urlString)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
