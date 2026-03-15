import SwiftUI

@main
struct ObsidianToolkitManagerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    loadInitialState()
                }
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    private func loadInitialState() {
        // Clear stale python path so it auto-detects from shell
        if UserDefaults.standard.string(forKey: "pythonPath") == "/usr/bin/python3" {
            UserDefaults.standard.removeObject(forKey: "pythonPath")
        }

        // Capture shell environment (so we see ~/.zshrc exports like API keys)
        appState.loadShellEnvironment()

        // Migrate or detect repo path
        if appState.repoPath.isEmpty {
            // Migrate from old toolkitPath if it ends in /toolkit
            if let oldPath = UserDefaults.standard.string(forKey: "toolkitPath"),
               oldPath.hasSuffix("/toolkit") {
                let candidate = String(oldPath.dropLast("/toolkit".count))
                if FileManager.default.fileExists(atPath: candidate + "/toolkit/manifest.json") {
                    appState.repoPath = candidate
                }
            }

            // Auto-detect canonical repo location
            if appState.repoPath.isEmpty {
                let defaultRepo = NSString("~/Desktop/ObsidianToolkitManager").expandingTildeInPath
                if FileManager.default.fileExists(atPath: defaultRepo + "/toolkit/manifest.json") {
                    appState.repoPath = defaultRepo
                }
            }
        }

        guard !appState.toolkitPath.isEmpty else { return }

        // Load config
        appState.config = ConfigService.load(from: appState.toolkitPath)

        // Load agents from manifest
        if let manifest = AgentDiscoveryService.loadManifest(toolkitPath: appState.toolkitPath) {
            appState.agents = manifest.agents
        }

        // Load audit summary
        appState.lastAuditSummary = ReportService.parseAuditSummary(toolkitPath: appState.toolkitPath)

        // Auto-start sync daemon
        if appState.autoStartSync, !appState.syncPath.isEmpty {
            appState.syncDaemon.start(
                syncPath: appState.syncPath,
                nodePath: appState.nodePath,
                environment: appState.shellEnvironment
            )
        }

        // Stop sync on app termination
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            appState.syncDaemon.stop()
        }
    }
}
