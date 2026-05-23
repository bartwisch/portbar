import SwiftUI

enum ServerFilter: String, CaseIterable, Identifiable {
    case development
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .development:
            "Dev"
        case .all:
            "Alle"
        }
    }
}

struct ServerListView: View {
    @ObservedObject var scanner: ServerScanner
    let onQuit: () -> Void

    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 5.0
    @AppStorage("forceKillEnabled") private var forceKillEnabled = true
    @AppStorage("ignoredProcessNames") private var ignoredProcessNames = "airplayxpchelper,controlcenter,google drive,rapportd,sharingd"
    @AppStorage("defaultFilter") private var defaultFilter = ServerFilter.development.rawValue

    @StateObject private var loginItemController = LoginItemController()
    @State private var filter: ServerFilter = .development
    @State private var isShowingSettings = false
    @State private var pendingStop: ServerProcess?
    @State private var refreshTask: Task<Void, Never>?

    private var visibleServers: [ServerProcess] {
        let ignoredNames = ignoredProcessNames
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let unignoredServers = scanner.servers.filter { server in
            !ignoredNames.contains(server.processName.lowercased())
        }

        return switch filter {
        case .development:
            unignoredServers.filter(\.isLikelyDevelopmentServer)
        case .all:
            unignoredServers
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            content
            Divider()
            footer
        }
        .frame(width: 390, height: 520)
        .alert(item: $pendingStop) { server in
            Alert(
                title: Text("Server stoppen?"),
                message: Text(stopMessage(for: server)),
                primaryButton: .destructive(Text("Stoppen")) {
                    scanner.stop(server, forceAfterDelay: forceKillEnabled)
                },
                secondaryButton: .cancel(Text("Abbrechen"))
            )
        }
        .onAppear {
            filter = ServerFilter(rawValue: defaultFilter) ?? .development
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: autoRefreshEnabled) { _, _ in
            startAutoRefresh()
        }
        .onChange(of: autoRefreshInterval) { _, _ in
            startAutoRefresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.title3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Laufende Server")
                    .font(.headline)
                Text("\(visibleServers.count) sichtbar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Einstellungen")
            .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                SettingsView(
                    autoRefreshEnabled: $autoRefreshEnabled,
                    autoRefreshInterval: $autoRefreshInterval,
                    forceKillEnabled: $forceKillEnabled,
                    ignoredProcessNames: $ignoredProcessNames,
                    defaultFilter: $defaultFilter
                )
            }

            Button {
                scanner.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Aktualisieren")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ServerFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if scanner.isLoading && scanner.servers.isEmpty {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        } else if visibleServers.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "network.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(filter == .development ? "Keine Dev-Server" : "Keine Listener")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleServers) { server in
                        ServerRow(
                            server: server,
                            onOpenURL: { scanner.open($0) },
                            onCopyURL: { scanner.copyURL($0) },
                            onCopyDefaultURL: { scanner.copyURL(server) },
                            onCopyPort: { scanner.copyPort(server) },
                            onStop: { pendingStop = server }
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage = scanner.errorMessage {
                Text(errorMessage)
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(scanner.isLoading ? "Aktualisiere..." : "Bereit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(isOn: Binding(
                get: { loginItemController.isEnabled },
                set: { loginItemController.setEnabled($0) }
            )) {
                Text("Autostart")
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            .help("PortBar beim Login starten")

            Button {
                onQuit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Beenden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func stopMessage(for server: ServerProcess) -> String {
        var message = "\(server.processName) (PID \(server.pid)) auf Port \(server.port) wird beendet."

        if forceKillEnabled {
            message += " Falls der Prozess nicht reagiert, wird er hart beendet."
        }

        return message
    }

    private func startAutoRefresh() {
        stopAutoRefresh()

        guard autoRefreshEnabled else {
            return
        }

        let interval = max(2.0, autoRefreshInterval)
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    scanner.refresh()
                }
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

private struct ServerRow: View {
    let server: ServerProcess
    let onOpenURL: (ServerURL) -> Void
    let onCopyURL: (ServerURL) -> Void
    let onCopyDefaultURL: () -> Void
    let onCopyPort: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: server.isLikelyDevelopmentServer ? "terminal" : "network")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.displayName)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text(":\(server.port)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(server.detailSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Menu {
                    ForEach(server.urlOptions) { serverURL in
                        Button {
                            onOpenURL(serverURL)
                        } label: {
                            Label(serverURL.urlString, systemImage: "safari")
                        }

                        Button {
                            onCopyURL(serverURL)
                        } label: {
                            Label("URL kopieren", systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("URL öffnen oder kopieren")

                Menu {
                    Button {
                        onCopyDefaultURL()
                    } label: {
                        Label("URL kopieren", systemImage: "link")
                    }

                    Button {
                        onCopyPort()
                    } label: {
                        Label("Port kopieren", systemImage: "number")
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Kopieren")

                Button(action: onStop) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Stoppen")
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    ServerListView(scanner: ServerScanner(), onQuit: {})
}

private struct SettingsView: View {
    @Binding var autoRefreshEnabled: Bool
    @Binding var autoRefreshInterval: Double
    @Binding var forceKillEnabled: Bool
    @Binding var ignoredProcessNames: String
    @Binding var defaultFilter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Einstellungen")
                    .font(.headline)
                Spacer()
            }

            Toggle("Auto-Refresh", isOn: $autoRefreshEnabled)

            HStack {
                Text("Intervall")
                Spacer()
                Stepper(
                    "\(Int(autoRefreshInterval)) s",
                    value: $autoRefreshInterval,
                    in: 2...30,
                    step: 1
                )
                .frame(width: 110)
            }
            .disabled(!autoRefreshEnabled)

            Toggle("Hard-Kill nach Timeout", isOn: $forceKillEnabled)

            Picker("Standardfilter", selection: $defaultFilter) {
                ForEach(ServerFilter.allCases) { filter in
                    Text(filter.title).tag(filter.rawValue)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ignorierte Prozesse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("prozess, anderer prozess", text: $ignoredProcessNames)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
