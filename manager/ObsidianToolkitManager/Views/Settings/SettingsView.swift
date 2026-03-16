import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var repoPath: String = ""
    @State private var pythonPath: String = ""
    @State private var vaultPath: String = ""
    @State private var inboxFolder: String = ""
    @State private var outputFolder: String = ""
    @State private var excludedFolders: [String] = []
    @State private var apiKeyEnv: String = ""
    @State private var newExcludedFolder: String = ""
    @State private var pythonTestResult: String?
    @State private var saveStatus: String?
    @State private var autoStartSync: Bool = true
    @State private var showSyncLogs: Bool = false
    @State private var updateState: UpdateState = .idle
    @State private var updateOutput: [String] = []
    @State private var showBuildOutput: Bool = false

    enum UpdateState: Equatable {
        case idle
        case running(step: String)
        case success
        case failed(String)
    }

    var body: some View {
        Form {
            repositorySection
            vaultSection
            excludedFoldersSection
            apiSection
            taskSyncSection
            appUpdateSection
            saveSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
        .navigationTitle("Settings")
        .onAppear {
            loadFromState()
        }
    }

    // MARK: - Repository

    private var repositorySection: some View {
        Section("Repository") {
            HStack {
                TextField("Repository Path", text: $repoPath)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        repoPath = url.path
                    }
                }
            }

            if !repoPath.isEmpty {
                LabeledContent("Toolkit") {
                    Text(repoPath + "/toolkit")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Sync") {
                    Text(repoPath + "/sync")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Manager") {
                    Text(repoPath + "/manager")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
    }

    // MARK: - Vault

    private var vaultSection: some View {
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
    }

    // MARK: - Excluded Folders

    private var excludedFoldersSection: some View {
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
    }

    // MARK: - API

    private var apiSection: some View {
        Section("API") {
            SecureField("Anthropic API Key", text: Binding(
                get: { appState.apiKey },
                set: { appState.apiKey = $0 }
            ))
            .help("Your Anthropic API key (starts with sk-ant-). Stored locally on this Mac.")

            HStack {
                let hasKey = !appState.apiKey.isEmpty || {
                    let envVar = apiKeyEnv.isEmpty ? "ANTHROPIC_API_KEY" : apiKeyEnv
                    return appState.shellEnvironment[envVar] != nil
                }()
                Image(systemName: hasKey ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(hasKey ? .green : .red)
                Text(hasKey ? "API key configured" : "No API key — AI features will be unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Task Sync

    private var taskSyncSection: some View {
        Section("Task Sync") {
            HStack {
                syncStatusDot
                Text(syncStatusLabel)
                    .font(.headline)
                Spacer()
                Button(appState.syncDaemon.status == .running ? "Stop" : "Start") {
                    if appState.syncDaemon.status == .running {
                        appState.syncDaemon.stop()
                    } else {
                        appState.syncDaemon.start(
                            syncPath: appState.syncPath,
                            nodePath: appState.nodePath,
                            environment: appState.effectiveEnvironment
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle("Auto-start with app", isOn: $autoStartSync)
                .onChange(of: autoStartSync) { _, newValue in
                    appState.autoStartSync = newValue
                }

            if let error = appState.syncDaemon.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            DisclosureGroup("Logs (\(appState.syncDaemon.recentOutput.count) lines)", isExpanded: $showSyncLogs) {
                ScrollView {
                    Text(appState.syncDaemon.recentOutput.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private var syncStatusDot: some View {
        Circle()
            .fill(syncDotColor)
            .frame(width: 10, height: 10)
    }

    private var syncDotColor: Color {
        switch appState.syncDaemon.status {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }

    private var syncStatusLabel: String {
        switch appState.syncDaemon.status {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .error: return "Error"
        }
    }

    // MARK: - App Update

    private var appUpdateSection: some View {
        Section("App Update") {
            HStack {
                Button("Update & Rebuild") {
                    Task { await runUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateState != .idle && updateState != .success && !isUpdateFailed)

                switch updateState {
                case .idle:
                    EmptyView()
                case .running(let step):
                    ProgressView()
                        .controlSize(.small)
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Build succeeded")
                            .font(.caption)
                        Button("Restart Now") {
                            SelfUpdateService.restart(managerPath: appState.managerPath)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                case .failed(let msg):
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }

            DisclosureGroup("Build Output (\(updateOutput.count) lines)", isExpanded: $showBuildOutput) {
                ScrollView {
                    Text(updateOutput.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private var isUpdateFailed: Bool {
        if case .failed = updateState { return true }
        return false
    }

    // MARK: - Save

    private var saveSection: some View {
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

    // MARK: - Actions

    private func loadFromState() {
        repoPath = appState.repoPath
        pythonPath = appState.pythonPath
        autoStartSync = appState.autoStartSync

        if let config = appState.config {
            vaultPath = config.vaultPath
            inboxFolder = config.inboxFolder
            outputFolder = config.outputFolder
            excludedFolders = config.excludedFolders
            apiKeyEnv = config.anthropicApiKeyEnv
        } else if !appState.toolkitPath.isEmpty {
            if let config = ConfigService.load(from: appState.toolkitPath) {
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
        appState.repoPath = repoPath
        appState.pythonPath = pythonPath
        appState.autoStartSync = autoStartSync

        let config = VaultConfig(
            vaultPath: vaultPath,
            inboxFolder: inboxFolder,
            outputFolder: outputFolder,
            excludedFolders: excludedFolders,
            anthropicApiKeyEnv: apiKeyEnv
        )

        do {
            try ConfigService.save(config, to: appState.toolkitPath)
            appState.config = config

            // Reload agents
            if let manifest = AgentDiscoveryService.loadManifest(toolkitPath: appState.toolkitPath) {
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

    private func runUpdate() async {
        let env = appState.effectiveEnvironment
        let managerPath = appState.managerPath
        let repoPath = appState.repoPath
        updateOutput = []

        guard !repoPath.isEmpty else {
            updateState = .failed("Repository path not configured")
            return
        }

        // Step 1: git pull
        updateState = .running(step: "Pulling latest changes...")
        var stepFailed = false
        for await output in SelfUpdateService.gitPull(repoPath: repoPath, environment: env) {
            switch output {
            case .stdout(let text): updateOutput.append(text)
            case .stderr(let text):
                updateOutput.append("[stderr] " + text)
                if text.contains("fatal") { stepFailed = true }
            case .exit(let code):
                if code != 0 { stepFailed = true }
            }
        }
        if stepFailed {
            updateState = .failed("Git pull failed")
            return
        }

        // Step 2: xcodegen
        updateState = .running(step: "Regenerating Xcode project...")
        stepFailed = false
        for await output in SelfUpdateService.xcodegen(managerPath: managerPath, environment: env) {
            switch output {
            case .stdout(let text): updateOutput.append(text)
            case .stderr(let text): updateOutput.append("[stderr] " + text)
            case .exit(let code):
                if code != 0 { stepFailed = true }
            }
        }
        if stepFailed {
            updateState = .failed("XcodeGen failed")
            return
        }

        // Step 3: xcodebuild
        updateState = .running(step: "Building release...")
        stepFailed = false
        for await output in SelfUpdateService.xcodebuild(managerPath: managerPath, environment: env) {
            switch output {
            case .stdout(let text): updateOutput.append(text)
            case .stderr(let text): updateOutput.append("[stderr] " + text)
            case .exit(let code):
                if code != 0 { stepFailed = true }
            }
        }
        if stepFailed {
            updateState = .failed("Build failed — check output")
            return
        }

        // Step 4: install
        updateState = .running(step: "Installing to /Applications...")
        stepFailed = false
        for await output in SelfUpdateService.install(managerPath: managerPath) {
            switch output {
            case .stdout(let text): updateOutput.append(text)
            case .stderr(let text): updateOutput.append("[stderr] " + text)
            case .exit(let code):
                if code != 0 { stepFailed = true }
            }
        }
        if stepFailed {
            updateState = .failed("Install failed — check output")
            return
        }

        updateState = .success
    }
}
