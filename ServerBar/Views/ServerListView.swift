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

    @StateObject private var loginItemController = LoginItemController()
    @State private var filter: ServerFilter = .development
    @State private var pendingStop: ServerProcess?

    private var visibleServers: [ServerProcess] {
        switch filter {
        case .development:
            scanner.servers.filter(\.isLikelyDevelopmentServer)
        case .all:
            scanner.servers
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
                message: Text("\(server.processName) (PID \(server.pid)) auf Port \(server.port) wird beendet."),
                primaryButton: .destructive(Text("Stoppen")) {
                    scanner.stop(server)
                },
                secondaryButton: .cancel(Text("Abbrechen"))
            )
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
