import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    let columns = [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                VaultHealthCard(summary: appState.lastAuditSummary)
                SyncStatusCard()

                ForEach(appState.agents) { agent in
                    AgentCard(
                        agent: agent,
                        lastRun: appState.lastRun(for: agent.id),
                        onRun: {
                            appState.selectedAgentId = agent.id
                            appState.selectedTab = .agentRunner
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}
