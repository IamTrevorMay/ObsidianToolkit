import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var toolkitPath: String = ""
    @State private var pythonPath: String = ""
    @State private var vaultPath: String = ""
    @State private var inboxFolder: String = ""
    @State private var outputFolder: String = ""
    @State private var excludedFolders: [String] = []
    @State private var apiKeyEnv: String = ""
    @State private var newExcludedFolder: String = ""
    @State private var pythonTestResult: String?
    @State private var saveStatus: String?

    var body: some View {
        Form {
            Section("Toolkit") {
                HStack {
                    TextField("Toolkit Path", text: $toolkitPath)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            toolkitPath = url.path
                        }
                    }
                }

                HStack {
                    TextField("Python Path", text: $pythonPath)
                    Button("Test") {
                        testPython()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let result = pythonTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("OK") ? .green : .red)
                }
            }

            Section("Vault") {
                HStack {
                    TextField("Vault Path", text: $vaultPath)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            vaultPath = url.path
                        }
                    }
                }

                TextField("Inbox Folder", text: $inboxFolder)
                TextField("Output Folder", text: $outputFolder)
            }

            Section("Excluded Folders") {
                ForEach(excludedFolders, id: \.self) { folder in
                    HStack {
                        Text(folder)
                        Spacer()
                        Button {
                            excludedFolders.removeAll { $0 == folder }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Add folder...", text: $newExcludedFolder)
                        .onSubmit { addExcludedFolder() }
                    Button {
                        addExcludedFolder()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newExcludedFolder.isEmpty)
                }
            }

            Section("API") {
                TextField("Environment variable name (e.g. ANTHROPIC_API_KEY)", text: $apiKeyEnv)
                    .help("The name of the environment variable that holds your API key — not the key itself.")

                if apiKeyEnv.hasPrefix("sk-") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("This field should contain the variable name (e.g. ANTHROPIC_API_KEY), not the key itself.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    let envVar = apiKeyEnv.isEmpty ? "ANTHROPIC_API_KEY" : apiKeyEnv
                    let hasKey = !envVar.hasPrefix("sk-") && !envVar.isEmpty && appState.shellEnvironment[envVar] != nil
                    Image(systemName: hasKey ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hasKey ? .green : .red)
                    Text(hasKey ? "API key found in $\(envVar)" : "API key not found in $\(envVar)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)

                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Error") ? .red : .green)
                    }

                    Spacer()

                    Button("Reload from Disk") {
                        loadFromState()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
        .navigationTitle("Settings")
        .onAppear {
            loadFromState()
        }
    }

    private func loadFromState() {
        toolkitPath = appState.toolkitPath
        pythonPath = appState.pythonPath

        if let config = appState.config {
            vaultPath = config.vaultPath
            inboxFolder = config.inboxFolder
            outputFolder = config.outputFolder
            excludedFolders = config.excludedFolders
            apiKeyEnv = config.anthropicApiKeyEnv
        } else if !toolkitPath.isEmpty {
            if let config = ConfigService.load(from: toolkitPath) {
                vaultPath = config.vaultPath
                inboxFolder = config.inboxFolder
                outputFolder = config.outputFolder
                excludedFolders = config.excludedFolders
                apiKeyEnv = config.anthropicApiKeyEnv
                appState.config = config
            }
        }

        saveStatus = nil
        pythonTestResult = nil
    }

    private func save() {
        appState.toolkitPath = toolkitPath
        appState.pythonPath = pythonPath

        let config = VaultConfig(
            vaultPath: vaultPath,
            inboxFolder: inboxFolder,
            outputFolder: outputFolder,
            excludedFolders: excludedFolders,
            anthropicApiKeyEnv: apiKeyEnv
        )

        do {
            try ConfigService.save(config, to: toolkitPath)
            appState.config = config

            // Reload agents
            if let manifest = AgentDiscoveryService.loadManifest(toolkitPath: toolkitPath) {
                appState.agents = manifest.agents
            }

            saveStatus = "Saved successfully"
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func addExcludedFolder() {
        let folder = newExcludedFolder.trimmingCharacters(in: .whitespaces)
        guard !folder.isEmpty, !excludedFolders.contains(folder) else { return }
        excludedFolders.append(folder)
        newExcludedFolder = ""
    }

    private func testPython() {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                pythonTestResult = "OK: \(output)"
            }
        } catch {
            pythonTestResult = "Error: \(error.localizedDescription)"
        }
    }
}
