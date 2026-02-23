import Foundation

public actor CodexRuntime {
    public typealias ExecutableResolver = @Sendable () -> String?

    let executableResolver: ExecutableResolver
    let environmentOverrides: [String: String]
    let correlator = RequestCorrelator()
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    var process: Process?
    var stdinHandle: FileHandle?
    var stdoutHandle: FileHandle?
    var stderrHandle: FileHandle?
    var framer = JSONLFramer()
    var stderrLineBuffer = Data()
    struct PendingApprovalRequest: Sendable {
        let rpcID: JSONRPCID
        let request: RuntimeApprovalRequest
    }

    var pendingApprovalRequests: [Int: PendingApprovalRequest] = [:]
    var nextLocalApprovalRequestID: Int = 1
    var runtimeCapabilities: RuntimeCapabilities = .none

    var stdoutPumpTask: Task<Void, Never>?
    var stderrPumpTask: Task<Void, Never>?
    var stdoutPumpContinuation: AsyncStream<Data>.Continuation?
    var stderrPumpContinuation: AsyncStream<Data>.Continuation?
    var stdoutBufferedBytes = 0
    var stderrBufferedBytes = 0
    var isStdoutReadPaused = false
    var isStderrReadPaused = false

    let eventStream: AsyncStream<CodexRuntimeEvent>
    let eventContinuation: AsyncStream<CodexRuntimeEvent>.Continuation

    static let ioBackpressurePauseHighWatermarkBytes = 2 * 1024 * 1024
    static let ioBackpressureResumeLowWatermarkBytes = 512 * 1024

    public init(
        executableResolver: @escaping ExecutableResolver = CodexRuntime.defaultExecutableResolver,
        environmentOverrides: [String: String] = [:]
    ) {
        self.executableResolver = executableResolver
        self.environmentOverrides = environmentOverrides

        var continuation: AsyncStream<CodexRuntimeEvent>.Continuation?
        eventStream = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        eventContinuation = continuation!
    }

    deinit {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutPumpContinuation?.finish()
        stderrPumpContinuation?.finish()
        stdoutPumpTask?.cancel()
        stderrPumpTask?.cancel()
        process?.terminate()
    }

    public func events() -> AsyncStream<CodexRuntimeEvent> {
        eventStream
    }

    public nonisolated static func defaultExecutableResolver() -> String? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = executableCandidates(
            pathEnv: envPath,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    static func executableCandidates(pathEnv: String, homeDirectory: URL) -> [String] {
        var searchDirectories = pathEnv
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        // GUI apps often get a minimal PATH. Search common Homebrew + user bin dirs too.
        searchDirectories.append("/opt/homebrew/bin")
        searchDirectories.append("/usr/local/bin")
        searchDirectories.append(homeDirectory.appendingPathComponent(".local/bin", isDirectory: true).path)
        searchDirectories.append(homeDirectory.appendingPathComponent("bin", isDirectory: true).path)

        var seen: Set<String> = []
        let uniqueDirectories = searchDirectories.filter { seen.insert($0).inserted }

        return uniqueDirectories.map { directory in
            URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
                .path
        }
    }

    nonisolated static func mergedEnvironment(
        base: [String: String],
        overrides: [String: String]
    ) -> [String: String] {
        base.merging(overrides) { _, new in new }
    }
}
