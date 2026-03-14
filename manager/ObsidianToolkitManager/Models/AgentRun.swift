import Foundation

struct AgentRunRecord: Identifiable {
    let id: UUID
    let agentId: String
    let startedAt: Date
    var finishedAt: Date?
    var status: RunStatus
    var stdout: String
    var stderr: String
    var exitCode: Int32?

    enum RunStatus: String {
        case running
        case succeeded
        case failed
        case cancelled
    }

    init(agentId: String) {
        self.id = UUID()
        self.agentId = agentId
        self.startedAt = Date()
        self.status = .running
        self.stdout = ""
        self.stderr = ""
    }
}
