import Foundation

struct AgentRunnerService {
    static func buildArguments(
        agent: AgentDefinition,
        parameterValues: [String: Any],
        configPath: String
    ) -> [String] {
        var args = ["-m", agent.module, "--config", configPath]

        for param in agent.parameters {
            guard let value = parameterValues[param.name] else { continue }

            switch param.type {
            case .bool:
                if let boolVal = value as? Bool, boolVal {
                    args.append(param.flag)
                }

            case .string:
                if let strVal = value as? String, !strVal.isEmpty {
                    args.append(param.flag)
                    args.append(strVal)
                }

            case .filePath:
                if let pathVal = value as? String, !pathVal.isEmpty {
                    args.append(param.flag)
                    args.append(pathVal)
                }

            case .stringArray:
                if let arrVal = value as? [String], !arrVal.isEmpty {
                    args.append(param.flag)
                    args.append(contentsOf: arrVal)
                } else if let strVal = value as? String, !strVal.isEmpty {
                    let items = strVal.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if !items.isEmpty {
                        args.append(param.flag)
                        args.append(contentsOf: items)
                    }
                }

            case .int:
                if let strVal = value as? String, !strVal.isEmpty {
                    args.append(param.flag)
                    args.append(strVal)
                }

            case .float:
                if let strVal = value as? String, !strVal.isEmpty {
                    args.append(param.flag)
                    args.append(strVal)
                }
            }
        }

        return args
    }

    static func runAgent(
        agent: AgentDefinition,
        parameterValues: [String: Any],
        pythonPath: String,
        toolkitPath: String,
        environment: [String: String] = [:]
    ) -> (UUID, AsyncStream<ProcessOutput>) {
        let configPath = (toolkitPath as NSString).appendingPathComponent("config.json")
        let arguments = buildArguments(
            agent: agent,
            parameterValues: parameterValues,
            configPath: configPath
        )

        let record = AgentRunRecord(agentId: agent.id)

        let stream = AsyncStream<ProcessOutput> { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: toolkitPath)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if !environment.isEmpty {
                process.environment = environment
            }

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                        continuation.yield(.stdout(line))
                    }
                }
            }

            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                        continuation.yield(.stderr(line))
                    }
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

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.stderr("Failed to launch: \(error.localizedDescription)"))
                continuation.yield(.exit(-1))
                continuation.finish()
            }
        }

        return (record.id, stream)
    }
}
