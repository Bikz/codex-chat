import CodexProcess
import Foundation

public enum ExtensionWorkerRunnerError: LocalizedError, Sendable {
    case invalidCommand
    case launchFailed(String)
    case timedOut(Int)
    case nonZeroExit(code: Int32, stderr: String)
    case outputTooLarge(Int)
    case malformedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCommand:
            "Extension handler command is empty."
        case let .launchFailed(message):
            "Failed to launch extension worker: \(message)"
        case let .timedOut(timeoutMs):
            "Extension worker timed out after \(timeoutMs)ms."
        case let .nonZeroExit(code, stderr):
            "Extension worker exited with status \(code): \(stderr)"
        case let .outputTooLarge(maxBytes):
            "Extension worker output exceeded limit (\(maxBytes) bytes)."
        case let .malformedOutput(detail):
            "Extension worker returned malformed output: \(detail)"
        }
    }
}

public struct ExtensionWorkerRunResult: Hashable, Sendable {
    public var output: ExtensionWorkerOutput
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(output: ExtensionWorkerOutput, stdout: String, stderr: String, exitCode: Int32) {
        self.output = output
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public actor ExtensionWorkerRunner {
    public init() {}

    public func run(
        handler: ExtensionHandlerDefinition,
        input: ExtensionWorkerInput,
        workingDirectory: URL,
        timeoutMs: Int,
        maxOutputBytes: Int = 256 * 1024
    ) async throws -> ExtensionWorkerRunResult {
        let configuredOutputLimit = max(1, maxOutputBytes)
        let command = handler.command.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let executable = command.first else {
            throw ExtensionWorkerRunnerError.invalidCommand
        }

        let executableURL: URL
        let arguments: [String]
        if executable.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: executable)
            arguments = command.count > 1 ? Array(command.dropFirst()) : []
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = command
        }

        let cwdURL: URL = if let cwd = handler.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            URL(fileURLWithPath: cwd, relativeTo: workingDirectory).standardizedFileURL
        } else {
            workingDirectory
        }

        var stdinData = try JSONEncoder().encode(input)
        stdinData.append(Data("\n".utf8))
        let limits = BoundedProcessRunner.Limits(
            timeoutMs: timeoutMs,
            maxOutputBytes: configuredOutputLimit
        )

        let detailed: BoundedProcessRunner.DetailedResult
        do {
            detailed = try BoundedProcessRunner.runDetailed(
                executableURL: executableURL,
                arguments: arguments,
                cwd: cwdURL,
                stdinData: stdinData,
                limits: limits
            )
        } catch let error as BoundedProcessRunner.RunnerError {
            switch error {
            case let .launchFailed(message):
                throw ExtensionWorkerRunnerError.launchFailed(message)
            case let .timedOut(timeoutMs, _, _):
                throw ExtensionWorkerRunnerError.timedOut(timeoutMs)
            }
        } catch {
            throw ExtensionWorkerRunnerError.launchFailed(error.localizedDescription)
        }

        let observedBytes = detailed.stdoutData.count + detailed.stderrData.count
        if observedBytes > configuredOutputLimit || detailed.stdoutTruncated || detailed.stderrTruncated {
            throw ExtensionWorkerRunnerError.outputTooLarge(configuredOutputLimit)
        }

        let exitCode = detailed.terminationStatus
        let stdoutData = detailed.stdoutData
        let stderrData = detailed.stderrData
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard exitCode == 0 else {
            throw ExtensionWorkerRunnerError.nonZeroExit(code: exitCode, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let line = stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !line.isEmpty else {
            throw ExtensionWorkerRunnerError.malformedOutput("Missing JSON line output")
        }

        guard let payload = line.data(using: .utf8) else {
            throw ExtensionWorkerRunnerError.malformedOutput("Invalid UTF-8 output")
        }

        let decoded: ExtensionWorkerOutput
        do {
            decoded = try JSONDecoder().decode(ExtensionWorkerOutput.self, from: payload)
        } catch {
            throw ExtensionWorkerRunnerError.malformedOutput(error.localizedDescription)
        }

        return ExtensionWorkerRunResult(output: decoded, stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}
