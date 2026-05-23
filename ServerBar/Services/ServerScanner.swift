import AppKit
import Darwin
import Foundation

enum ServerScannerError: LocalizedError, Sendable {
    case lsofFailed(String)

    var errorDescription: String? {
        switch self {
        case .lsofFailed(let message):
            message.isEmpty ? "lsof konnte nicht ausgeführt werden." : message
        }
    }
}

@MainActor
final class ServerScanner: ObservableObject {
    @Published private(set) var servers: [ServerProcess] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refresh() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                servers = try await Self.scanInBackground()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func open(_ server: ServerProcess) {
        openURLString(server.urlString)
    }

    func open(_ serverURL: ServerURL) {
        openURLString(serverURL.urlString)
    }

    func copyURL(_ server: ServerProcess) {
        copyToPasteboard(server.urlString)
    }

    func copyURL(_ serverURL: ServerURL) {
        copyToPasteboard(serverURL.urlString)
    }

    func copyPort(_ server: ServerProcess) {
        copyToPasteboard(String(server.port))
    }

    private func openURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "Ungültige URL: \(urlString)"
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func stop(_ server: ServerProcess) {
        let result = Darwin.kill(server.pid, SIGTERM)

        guard result == 0 else {
            let message = String(cString: strerror(errno))
            errorMessage = "\(server.processName) konnte nicht beendet werden: \(message)"
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    nonisolated private static func scanInBackground() async throws -> [ServerProcess] {
        try await Task.detached(priority: .userInitiated) {
            try runLsof()
        }.value
    }

    nonisolated private static func runLsof() throws -> [ServerProcess] {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpctn"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 || !output.isEmpty else {
            throw ServerScannerError.lsofFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let servers = parseLsofOutput(output)
        let metadata = loadProcessMetadata(for: servers.map(\.pid))

        return servers.map { server in
            let processMetadata = metadata[server.pid]

            return ServerProcess(
                pid: server.pid,
                processName: server.processName,
                port: server.port,
                boundHosts: server.boundHosts,
                openHost: server.openHost,
                workingDirectory: processMetadata?.workingDirectory,
                projectName: processMetadata?.projectName
            )
        }
    }

    nonisolated static func parseLsofOutput(_ output: String) -> [ServerProcess] {
        struct EndpointKey: Hashable {
            let pid: pid_t
            let port: Int
        }

        struct PartialEndpoint {
            var pid: pid_t
            var processName: String
            var port: Int
            var boundHosts: Set<String>
            var openHost: String
        }

        var currentPID: pid_t?
        var currentCommand = ""
        var endpoints: [EndpointKey: PartialEndpoint] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let prefix = line.first else {
                continue
            }

            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = pid_t(value) ?? 0
                currentCommand = ""
            case "c":
                currentCommand = value
            case "n":
                guard let pid = currentPID, pid > 0, let endpoint = parseEndpoint(value) else {
                    continue
                }

                let key = EndpointKey(pid: pid, port: endpoint.port)
                var partial = endpoints[key] ?? PartialEndpoint(
                    pid: pid,
                    processName: currentCommand,
                    port: endpoint.port,
                    boundHosts: [],
                    openHost: endpoint.openHost
                )

                if partial.processName.isEmpty {
                    partial.processName = currentCommand
                }
                partial.boundHosts.insert(endpoint.displayHost)

                if partial.openHost == "localhost", endpoint.openHost != "localhost" {
                    partial.openHost = endpoint.openHost
                }

                endpoints[key] = partial
            default:
                continue
            }
        }

        return endpoints.values
            .map {
                ServerProcess(
                    pid: $0.pid,
                    processName: $0.processName.isEmpty ? "unknown" : $0.processName,
                    port: $0.port,
                    boundHosts: $0.boundHosts.sorted(),
                    openHost: $0.openHost,
                    workingDirectory: nil,
                    projectName: nil
                )
            }
            .sorted {
                if $0.port == $1.port {
                    return $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending
                }
                return $0.port < $1.port
            }
    }

    nonisolated private static func parseEndpoint(_ value: String) -> (displayHost: String, openHost: String, port: Int)? {
        guard let separator = value.lastIndex(of: ":") else {
            return nil
        }

        let rawHost = String(value[..<separator])
        let rawPort = String(value[value.index(after: separator)...])

        guard let port = Int(rawPort) else {
            return nil
        }

        let normalizedHost = normalizeHost(rawHost)
        let openHost = hostForOpening(normalizedHost)

        return (normalizedHost, openHost, port)
    }

    nonisolated private static func normalizeHost(_ host: String) -> String {
        var normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }

        switch normalized {
        case "*", "", "::", "0.0.0.0":
            return "localhost"
        case "::1", "127.0.0.1":
            return "localhost"
        default:
            return normalized
        }
    }

    nonisolated private static func hostForOpening(_ host: String) -> String {
        host == "localhost" ? "localhost" : host
    }

    nonisolated private static func loadProcessMetadata(for pids: [pid_t]) -> [pid_t: ProcessMetadata] {
        let uniquePIDs = Array(Set(pids)).sorted()

        guard !uniquePIDs.isEmpty else {
            return [:]
        }

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", uniquePIDs.map(String.init).joined(separator: ","), "-d", "cwd", "-Fn"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let cwdByPID = parseCwdOutput(output)

        return cwdByPID.mapValues { workingDirectory in
            ProcessMetadata(
                workingDirectory: workingDirectory,
                projectName: inferProjectName(from: workingDirectory)
            )
        }
    }

    nonisolated static func parseCwdOutput(_ output: String) -> [pid_t: String] {
        var currentPID: pid_t?
        var cwdByPID: [pid_t: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let prefix = line.first else {
                continue
            }

            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = pid_t(value) ?? 0
            case "n":
                guard let pid = currentPID, pid > 0 else {
                    continue
                }
                cwdByPID[pid] = value
            default:
                continue
            }
        }

        return cwdByPID
    }

    nonisolated private static func inferProjectName(from workingDirectory: String) -> String? {
        let url = URL(fileURLWithPath: workingDirectory)
        let packageURL = url.appendingPathComponent("package.json")

        if let packageData = try? Data(contentsOf: packageURL),
           let packageObject = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
           let packageName = packageObject["name"] as? String,
           !packageName.isEmpty {
            return packageName
        }

        let lastPathComponent = url.lastPathComponent
        return lastPathComponent.isEmpty ? nil : lastPathComponent
    }
}

struct ProcessMetadata: Sendable {
    let workingDirectory: String
    let projectName: String?
}
