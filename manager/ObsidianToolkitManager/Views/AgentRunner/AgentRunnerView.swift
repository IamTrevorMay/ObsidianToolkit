import SwiftUI

struct AgentRunnerView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedAgent: AgentDefinition?
    @State private var parameterValues: [String: Any] = [:]
    @State private var outputLines: [OutputLine] = []
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let isStderr: Bool
    }

    var body: some View {
        HSplitView {
            // Left: Agent list
            List(appState.agents, selection: Binding(
                get: { selectedAgent?.id },
                set: { id in
                    selectedAgent = appState.agents.first { $0.id == id }
                    if selectedAgent != nil {
                        resetForm()
                    }
                }
            )) { agent in
                HStack {
                    Image(systemName: agent.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(agent.name)
                            .font(.body)
                        Text(agent.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(agent.id)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, maxWidth: 280)

            // Right: Form + Output
            if let agent = selectedAgent {
                VStack(spacing: 0) {
                    // Agent header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: agent.icon)
                                .font(.title2)
                                .foregroundStyle(.blue)
                            Text(agent.name)
                                .font(.title2.bold())
                        }
                        Text(agent.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    Divider()

                    // Parameter form
                    ScrollView {
                        AgentParameterForm(
                            parameters: agent.parameters,
                            values: $parameterValues
                        )
                        .padding()
                    }
                    .frame(maxHeight: 300)

                    Divider()

                    // Action buttons
                    HStack {
                        Button("Run") {
                            runAgent(agent: agent, dryRun: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)

                        if agent.parameters.contains(where: { $0.name == "dry_run" }) {
                            Button("Dry Run") {
                                runAgent(agent: agent, dryRun: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }

                        if isRunning {
                            Button("Cancel") {
                                runTask?.cancel()
                                isRunning = false
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        Spacer()

                        if !outputLines.isEmpty {
                            Button("Clear Output") {
                                outputLines.removeAll()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    // Output
                    RunOutputView(lines: outputLines, isRunning: isRunning)
                }
            } else {
                ContentUnavailableView(
                    "Select an Agent",
                    systemImage: "terminal",
                    description: Text("Choose an agent from the list to configure and run it.")
                )
            }
        }
        .navigationTitle("Agent Runner")
        .onAppear {
            if let id = appState.selectedAgentId {
                selectedAgent = appState.agents.first { $0.id == id }
                appState.selectedAgentId = nil
                if selectedAgent != nil { resetForm() }
            }
        }
    }

    private func resetForm() {
        parameterValues = [:]
        guard let agent = selectedAgent else { return }
        for param in agent.parameters {
            switch param.type {
            case .bool:
                if case .bool(let val) = param.defaultValue {
                    parameterValues[param.name] = val
                } else {
                    parameterValues[param.name] = false
                }
            case .string, .filePath:
                if case .string(let val) = param.defaultValue {
                    parameterValues[param.name] = val
                } else {
                    parameterValues[param.name] = ""
                }
            case .stringArray:
                parameterValues[param.name] = ""
            case .int:
                if case .int(let val) = param.defaultValue {
                    parameterValues[param.name] = String(val)
                } else {
                    parameterValues[param.name] = ""
                }
            case .float:
                if case .float(let val) = param.defaultValue {
                    parameterValues[param.name] = String(val)
                } else {
                    parameterValues[param.name] = ""
                }
            }
        }
    }

    private func runAgent(agent: AgentDefinition, dryRun: Bool) {
        var values = parameterValues
        if dryRun {
            values["dry_run"] = true
        }

        outputLines.removeAll()
        isRunning = true

        var record = AgentRunRecord(agentId: agent.id)

        runTask = Task {
            let (_, stream) = AgentRunnerService.runAgent(
                agent: agent,
                parameterValues: values,
                pythonPath: appState.pythonPath,
                toolkitPath: appState.toolkitPath,
                environment: appState.effectiveEnvironment
            )

            for await output in stream {
                guard !Task.isCancelled else {
                    record.status = .cancelled
                    record.finishedAt = Date()
                    break
                }

                await MainActor.run {
                    switch output {
                    case .stdout(let line):
                        outputLines.append(OutputLine(text: line, isStderr: false))
                        record.stdout += line + "\n"
                    case .stderr(let line):
                        outputLines.append(OutputLine(text: line, isStderr: true))
                        record.stderr += line + "\n"
                    case .exit(let code):
                        record.exitCode = code
                        record.status = code == 0 ? .succeeded : .failed
                        record.finishedAt = Date()
                        isRunning = false
                    }
                }
            }

            await MainActor.run {
                if record.status == .running {
                    record.status = .cancelled
                    record.finishedAt = Date()
                }
                isRunning = false
                appState.runHistory.append(record)

                // Refresh audit summary if we just ran a vault audit
                if agent.id == "vault_audit" && record.status == .succeeded {
                    appState.lastAuditSummary = ReportService.parseAuditSummary(
                        toolkitPath: appState.toolkitPath
                    )
                }
            }
        }
    }
}
