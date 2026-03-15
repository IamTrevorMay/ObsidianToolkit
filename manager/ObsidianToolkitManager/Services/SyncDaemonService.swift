import Foundation

@Observable
final class SyncDaemonService {
    enum Status: String {
        case stopped, starting, running, error
    }

    private(set) var status: Status = .stopped
    private(set) var recentOutput: [String] = []
    private(set) var lastError: String?
    private var process: Process?

    func start(syncPath: String, nodePath: String, environment: [String: String]) {
        guard status != .running, status != .starting else { return }

        let indexPath = syncPath + "/index.js"
        let envPath = syncPath + "/.env"
        let modulesPath = syncPath + "/node_modules"

        guard FileManager.default.fileExists(atPath: indexPath) else {
            lastError = "index.js not found at \(syncPath)"
            status = .error
            return
        }

        guard FileManager.default.fileExists(atPath: envPath) else {
            lastError = ".env not found — create \(envPath) first"
            status = .error
            return
        }

        guard FileManager.default.isReadableFile(atPath: modulesPath) else {
            lastError = "node_modules missing — run npm install in \(syncPath)"
            status = .error
            return
        }

        status = .starting
        lastError = nil
        recentOutput = []

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: nodePath)
        proc.arguments = ["index.js"]
        proc.currentDirectoryURL = URL(fileURLWithPath: syncPath)
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.environment = environment

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput("[stderr] " + line)
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if self?.status == .running || self?.status == .starting {
                    if p.terminationStatus == 0 {
                        self?.status = .stopped
                    } else {
                        self?.lastError = "Process exited with code \(p.terminationStatus)"
                        self?.status = .error
                    }
                }
                self?.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
            status = .running
        } catch {
            lastError = error.localizedDescription
            status = .error
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else {
            status = .stopped
            return
        }
        status = .stopped
        proc.terminate()
    }

    private func appendOutput(_ text: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        recentOutput.append(contentsOf: lines)
        if recentOutput.count > 200 {
            recentOutput = Array(recentOutput.suffix(200))
        }
    }
}
