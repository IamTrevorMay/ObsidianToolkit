import Foundation

enum ProcessOutput {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

actor ProcessRunner {
    private var runningProcess: Process?

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) -> AsyncStream<ProcessOutput> {
        AsyncStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let wd = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: wd)
            }

            if let env = environment {
                var processEnv = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    processEnv[key] = value
                }
                process.environment = processEnv
            }

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        continuation.yield(.stdout(line))
                    }
                }
            }

            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        continuation.yield(.stderr(line))
                    }
                }
            }

            process.terminationHandler = { proc in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                // Read any remaining data
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

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
                Task { [weak self] in await self?.setProcess(process) }
            } catch {
                continuation.yield(.stderr("Failed to launch process: \(error.localizedDescription)"))
                continuation.yield(.exit(-1))
                continuation.finish()
            }
        }
    }

    func cancel() {
        runningProcess?.terminate()
        runningProcess = nil
    }

    private func setProcess(_ process: Process) {
        runningProcess = process
    }
}
