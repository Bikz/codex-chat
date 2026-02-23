import Foundation
import Darwin

public enum BoundedProcessRunner {
    public struct Limits: Hashable, Sendable {
        public let timeoutMs: Int
        public let maxOutputBytes: Int

        public init(timeoutMs: Int = 120_000, maxOutputBytes: Int = 131_072) {
            self.timeoutMs = max(100, timeoutMs)
            self.maxOutputBytes = max(1_024, maxOutputBytes)
        }

        public static func fromEnvironment(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            timeoutKey: String = "CODEX_PROCESS_TIMEOUT_MS",
            maxOutputBytesKey: String = "CODEX_PROCESS_MAX_OUTPUT_BYTES",
            defaultTimeoutMs: Int = 120_000,
            defaultMaxOutputBytes: Int = 131_072
        ) -> Limits {
            let timeoutMs = Int(environment[timeoutKey] ?? "") ?? defaultTimeoutMs
            let maxOutputBytes = Int(environment[maxOutputBytesKey] ?? "") ?? defaultMaxOutputBytes
            return Limits(timeoutMs: timeoutMs, maxOutputBytes: maxOutputBytes)
        }
    }

    public struct Result: Hashable, Sendable {
        public let output: String
        public let terminationStatus: Int32
        public let truncated: Bool

        public init(output: String, terminationStatus: Int32, truncated: Bool) {
            self.output = output
            self.terminationStatus = terminationStatus
            self.truncated = truncated
        }
    }

    public struct DetailedResult: Hashable, Sendable {
        public let stdoutData: Data
        public let stderrData: Data
        public let terminationStatus: Int32
        public let stdoutTruncated: Bool
        public let stderrTruncated: Bool

        public init(
            stdoutData: Data,
            stderrData: Data,
            terminationStatus: Int32,
            stdoutTruncated: Bool,
            stderrTruncated: Bool
        ) {
            self.stdoutData = stdoutData
            self.stderrData = stderrData
            self.terminationStatus = terminationStatus
            self.stdoutTruncated = stdoutTruncated
            self.stderrTruncated = stderrTruncated
        }
    }

    public enum RunnerError: Error, LocalizedError {
        case launchFailed(String)
        case timedOut(timeoutMs: Int, partialOutput: String, truncated: Bool)

        public var errorDescription: String? {
            switch self {
            case let .launchFailed(message):
                "Failed to launch process: \(message)"
            case let .timedOut(timeoutMs, _, _):
                "Timed out after \(timeoutMs)ms"
            }
        }
    }

    public static func run(
        _ argv: [String],
        cwd: String?,
        limits: Limits = Limits()
    ) throws -> Result {
        let detailed = try runDetailed(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: argv,
            cwd: cwd.map { URL(fileURLWithPath: $0, isDirectory: true) },
            stdinData: nil,
            limits: limits
        )
        let stdout = String(data: detailed.stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: detailed.stderrData, encoding: .utf8) ?? ""
        let merged = [stdout, stderr]
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return Result(
            output: merged,
            terminationStatus: detailed.terminationStatus,
            truncated: detailed.stdoutTruncated || detailed.stderrTruncated
        )
    }

    public static func runDetailed(
        executableURL: URL,
        arguments: [String],
        cwd: URL?,
        stdinData: Data?,
        limits: Limits = Limits()
    ) throws -> DetailedResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = cwd

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = CappedOutputCollector(maxBytes: limits.maxOutputBytes)
        let stderrCollector = CappedOutputCollector(maxBytes: limits.maxOutputBytes)
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdinHandle = stdinPipe.fileHandleForWriting

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stdoutCollector.append(data)
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stderrCollector.append(data)
        }

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        do {
            try process.run()
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            try? stdinHandle.close()
            throw RunnerError.launchFailed(error.localizedDescription)
        }

        if let stdinData {
            try? stdinHandle.write(contentsOf: stdinData)
        }
        try? stdinHandle.close()

        if completion.wait(timeout: .now() + .milliseconds(limits.timeoutMs)) == .timedOut {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            process.terminate()
            usleep(200_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            stdoutCollector.append(stdoutHandle.readDataToEndOfFile())
            stderrCollector.append(stderrHandle.readDataToEndOfFile())
            let stdoutSnapshot = stdoutCollector.snapshot()
            let stderrSnapshot = stderrCollector.snapshot()
            let partialStdout = String(data: stdoutSnapshot.data, encoding: .utf8) ?? ""
            let partialStderr = String(data: stderrSnapshot.data, encoding: .utf8) ?? ""
            let partialOutput = [partialStdout, partialStderr]
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            throw RunnerError.timedOut(
                timeoutMs: limits.timeoutMs,
                partialOutput: partialOutput,
                truncated: stdoutSnapshot.truncated || stderrSnapshot.truncated
            )
        }

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        stdoutCollector.append(stdoutHandle.readDataToEndOfFile())
        stderrCollector.append(stderrHandle.readDataToEndOfFile())

        let stdoutSnapshot = stdoutCollector.snapshot()
        let stderrSnapshot = stderrCollector.snapshot()
        return DetailedResult(
            stdoutData: stdoutSnapshot.data,
            stderrData: stderrSnapshot.data,
            terminationStatus: process.terminationStatus,
            stdoutTruncated: stdoutSnapshot.truncated,
            stderrTruncated: stderrSnapshot.truncated
        )
    }

    private final class CappedOutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let maxBytes: Int
        private var data = Data()
        private var truncated = false

        init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }

            guard data.count < maxBytes else {
                truncated = true
                return
            }

            let remaining = maxBytes - data.count
            if chunk.count > remaining {
                data.append(chunk.prefix(remaining))
                truncated = true
            } else {
                data.append(chunk)
            }
        }

        func snapshot() -> (data: Data, truncated: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (data, truncated)
        }
    }
}
