import SwiftUI

struct VaultHealthCard: View {
    let summary: AuditSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 32, height: 32)

                Text("Vault Health")
                    .font(.headline)

                Spacer()
            }

            if let summary {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    metricView(value: "\(summary.fileCount)", label: "Files")
                    metricView(value: "\(summary.uniqueTags)", label: "Tags")
                    metricView(value: "\(summary.brokenLinks)", label: "Broken Links", alert: summary.brokenLinks > 0)
                }

                if let date = summary.generatedAt {
                    Text("Last audit: \(date, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No audit data available. Run a Vault Audit to see health metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func metricView(value: String, label: String, alert: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(alert ? .red : .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
