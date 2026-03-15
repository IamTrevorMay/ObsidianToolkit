import SwiftUI

struct SyncStatusCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(dotColor)
                    .frame(width: 32, height: 32)

                Text("Task Sync")
                    .font(.headline)

                Spacer()

                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
            }

            HStack {
                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(appState.syncDaemon.status == .running ? "Stop" : "Start") {
                    if appState.syncDaemon.status == .running {
                        appState.syncDaemon.stop()
                    } else {
                        appState.syncDaemon.start(
                            syncPath: appState.syncPath,
                            nodePath: appState.nodePath,
                            environment: appState.shellEnvironment
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let error = appState.syncDaemon.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if !appState.syncDaemon.recentOutput.isEmpty {
                Text("\(appState.syncDaemon.recentOutput.count) log lines")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var dotColor: Color {
        switch appState.syncDaemon.status {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }

    private var statusLabel: String {
        switch appState.syncDaemon.status {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .error: return "Error"
        }
    }
}
