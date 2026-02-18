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
        let command = handler.command.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let executable = command.first else {
            throw ExtensionWorkerRunnerError.invalidCommand
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            if command.count > 1 {
                process.arguments = Array(command.dropFirst())
            }
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }

        if let cwd = handler.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, relativeTo: workingDirectory).standardizedFileURL
        } else {
            process.currentDirectoryURL = workingDirectory
        }

        let encodedInput = try JSONEncoder().encode(input)

        do {
            try process.run()
        } catch {
            throw ExtensionWorkerRunnerError.launchFailed(error.localizedDescription)
        }

        if let handle = Optional(stdinPipe.fileHandleForWriting) {
            try? handle.write(contentsOf: encodedInput)
            try? handle.write(contentsOf: Data("\n".utf8))
            try? handle.close()
        }

        let stdoutDataTask = Task { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
        let stderrDataTask = Task { stderrPipe.fileHandleForReading.readDataToEndOfFile() }

        let exitCode = try await waitForExit(process: process, timeoutMs: timeoutMs)

        let stdoutData = await stdoutDataTask.value
        let stderrData = await stderrDataTask.value

        if stdoutData.count > maxOutputBytes || stderrData.count > maxOutputBytes {
            throw ExtensionWorkerRunnerError.outputTooLarge(maxOutputBytes)
        }

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

    private func waitForExit(process: Process, timeoutMs: Int) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    process.terminationHandler = { terminated in
                        continuation.resume(returning: terminated.terminationStatus)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                if process.isRunning {
                    process.terminate()
                    throw ExtensionWorkerRunnerError.timedOut(timeoutMs)
                }
                return process.terminationStatus
            }

            guard let first = try await group.next() else {
                throw ExtensionWorkerRunnerError.launchFailed("Process exit wait failed")
            }

            group.cancelAll()
            return first
        }
    }
}
