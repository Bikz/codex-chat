import Foundation

public actor CodexRuntime {
    public typealias ExecutableResolver = @Sendable () -> String?

    let executableResolver: ExecutableResolver
    let correlator = RequestCorrelator()
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    var process: Process?
    var stdinHandle: FileHandle?
    var stdoutHandle: FileHandle?
    var stderrHandle: FileHandle?
    var framer = JSONLFramer()
    var pendingApprovalRequests: [Int: RuntimeApprovalRequest] = [:]

    var stdoutPumpTask: Task<Void, Never>?
    var stderrPumpTask: Task<Void, Never>?
    var stdoutPumpContinuation: AsyncStream<Data>.Continuation?
    var stderrPumpContinuation: AsyncStream<Data>.Continuation?

    let eventStream: AsyncStream<CodexRuntimeEvent>
    let eventContinuation: AsyncStream<CodexRuntimeEvent>.Continuation

    public init(executableResolver: @escaping ExecutableResolver = CodexRuntime.defaultExecutableResolver) {
        self.executableResolver = executableResolver

        var continuation: AsyncStream<CodexRuntimeEvent>.Continuation?
        eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(512)) { continuation = $0 }
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
}
