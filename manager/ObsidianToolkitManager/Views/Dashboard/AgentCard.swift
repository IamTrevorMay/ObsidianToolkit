import SwiftUI

struct AgentCard: View {
    let agent: AgentDefinition
    let lastRun: AgentRunRecord?
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: agent.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                    if let lastRun {
                        HStack(spacing: 4) {
                            statusIndicator(for: lastRun.status)
                            Text(lastRun.startedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }

            Text(agent.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text("\(agent.parameters.count) parameters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Run", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    @ViewBuilder
    private func statusIndicator(for status: AgentRunRecord.RunStatus) -> some View {
        Circle()
            .fill(statusColor(for: status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(for status: AgentRunRecord.RunStatus) -> Color {
        switch status {
        case .running: .orange
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .gray
        }
    }
}
