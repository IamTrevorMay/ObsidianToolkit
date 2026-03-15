import Foundation
import AppKit

enum SelfUpdateService {

    // MARK: - Steps

    static func gitPull(repoPath: String, environment: [String: String]) -> AsyncStream<ProcessOutput> {
        runProcess(
            executable: findExecutable("git", environment: environment) ?? "/usr/bin/git",
            arguments: ["pull", "--ff-only"],
            currentDirectory: repoPath,
            environment: environment
        )
    }

    static func xcodegen(managerPath: String, environment: [String: String]) -> AsyncStream<ProcessOutput> {
        guard let exe = findExecutable("xcodegen", environment: environment) else {
            return AsyncStream { $0.yield(.stderr("xcodegen not found in PATH")); $0.yield(.exit(1)); $0.finish() }
        }
        return runProcess(
            executable: exe,
            arguments: ["generate"],
            currentDirectory: managerPath,
            environment: environment
        )
    }

    static func xcodebuild(managerPath: String, environment: [String: String]) -> AsyncStream<ProcessOutput> {
        let exe = findExecutable("xcodebuild", environment: environment) ?? "/usr/bin/xcodebuild"
        return runProcess(
            executable: exe,
            arguments: [
                "-scheme", "ObsidianToolkitManager",
                "-configuration", "Release",
                "-derivedDataPath", managerPath + "/build",
                "build"
            ],
            currentDirectory: managerPath,
            environment: environment
        )
    }

    static func install(managerPath: String) -> AsyncStream<ProcessOutput> {
        let buildApp = managerPath + "/build/Build/Products/Release/ObsidianToolkitManager.app"
        let dest = "/Applications/ObsidianToolkitManager.app"

        return AsyncStream { continuation in
            let fm = FileManager.default
            guard fm.fileExists(atPath: buildApp) else {
                continuation.yield(.stderr("Built app not found at \(buildApp)"))
                continuation.yield(.exit(1))
                continuation.finish()
                return
            }

            do {
                if fm.fileExists(atPath: dest) {
                    try fm.removeItem(atPath: dest)
                }
                try fm.copyItem(atPath: buildApp, toPath: dest)
                continuation.yield(.stdout("Installed to \(dest)"))
                continuation.yield(.exit(0))
            } catch {
                continuation.yield(.stderr("Install error: \(error.localizedDescription)"))
                continuation.yield(.exit(1))
            }
            continuation.finish()
        }
    }

    static func restart(managerPath: String) {
        let appPath = "/Applications/ObsidianToolkitManager.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appPath]
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Helpers

    static func findExecutable(_ name: String, environment: [String: String]) -> String? {
        guard let path = environment["PATH"] else { return nil }
        for dir in path.components(separatedBy: ":") {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String,
        environment: [String: String]
    ) -> AsyncStream<ProcessOutput> {
        AsyncStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = environment

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    continuation.yield(.stdout(line))
                }
            }

            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    continuation.yield(.stderr(line))
                }
            }

            process.terminationHandler = { proc in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                let remainingStdout = stdoutHandle.readDataToEndOfFile()
                if !remainingStdout.isEmpty, let str = String(data: remainingStdout, encoding: .utf8) {
                    for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                        continuation.yield(.stdout(line))
                    }
                }
                let remainingStderr = stderrHandle.readDataToEndOfFile()
                if !remainingStderr.isEmpty, let str = String(data: remainingStderr, encoding: .utf8) {
                    for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                        continuation.yield(.stderr(line))
                    }
                }

                continuation.yield(.exit(proc.terminationStatus))
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.stderr("Failed to launch \(executable): \(error.localizedDescription)"))
                continuation.yield(.exit(1))
                continuation.finish()
            }
        }
    }
}
