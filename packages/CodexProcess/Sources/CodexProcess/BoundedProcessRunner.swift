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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let collector = CappedOutputCollector(maxBytes: limits.maxOutputBytes)
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            collector.append(data)
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            collector.append(data)
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
            throw RunnerError.launchFailed(error.localizedDescription)
        }

        if completion.wait(timeout: .now() + .milliseconds(limits.timeoutMs)) == .timedOut {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            process.terminate()
            usleep(200_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            collector.append(stdoutHandle.readDataToEndOfFile())
            collector.append(stderrHandle.readDataToEndOfFile())
            let snapshot = collector.snapshot()
            let partialOutput = String(bytes: snapshot.data, encoding: .utf8) ?? ""
            throw RunnerError.timedOut(
                timeoutMs: limits.timeoutMs,
                partialOutput: partialOutput,
                truncated: snapshot.truncated
            )
        }

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        collector.append(stdoutHandle.readDataToEndOfFile())
        collector.append(stderrHandle.readDataToEndOfFile())

        let snapshot = collector.snapshot()
        let merged = String(bytes: snapshot.data, encoding: .utf8) ?? ""
        return Result(
            output: merged,
            terminationStatus: process.terminationStatus,
            truncated: snapshot.truncated
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
