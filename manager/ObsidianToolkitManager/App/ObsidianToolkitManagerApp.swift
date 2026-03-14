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

        // Set default toolkit path if not configured
        if appState.toolkitPath.isEmpty {
            let defaultPath = NSString("~/Desktop/ObsidianTools/toolkit").expandingTildeInPath
            if FileManager.default.fileExists(atPath: defaultPath) {
                appState.toolkitPath = defaultPath
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
    }
}
