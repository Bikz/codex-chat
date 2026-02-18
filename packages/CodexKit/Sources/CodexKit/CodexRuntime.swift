import Foundation

public actor CodexRuntime {
    public typealias ExecutableResolver = @Sendable () -> String?

    private let executableResolver: ExecutableResolver
    private let correlator = RequestCorrelator()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var framer = JSONLFramer()

    private let eventStream: AsyncStream<CodexRuntimeEvent>
    private let eventContinuation: AsyncStream<CodexRuntimeEvent>.Continuation

    public init(executableResolver: @escaping ExecutableResolver = CodexRuntime.defaultExecutableResolver) {
        self.executableResolver = executableResolver

        var continuation: AsyncStream<CodexRuntimeEvent>.Continuation?
        self.eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(512)) { continuation = $0 }
        self.eventContinuation = continuation!
    }

    deinit {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        process?.terminate()
    }

    public func events() -> AsyncStream<CodexRuntimeEvent> {
        eventStream
    }

    public func start() async throws {
        if process != nil {
            return
        }

        guard let executablePath = executableResolver() else {
            throw CodexRuntimeError.binaryNotFound
        }

        try await spawnProcess(executablePath: executablePath)

        do {
            try await performHandshake()
        } catch {
            await stopProcess()
            throw CodexRuntimeError.handshakeFailed(error.localizedDescription)
        }
    }

    public func restart() async throws {
        await stopProcess()
        try await start()
    }

    public func stop() async {
        await stopProcess()
    }

    public func startThread(cwd: String? = nil) async throws -> String {
        try await start()

        var params: [String: JSONValue] = [:]
        if let cwd {
            params["cwd"] = .string(cwd)
        }

        let result = try await sendRequest(method: "thread/start", params: .object(params))
        guard let threadID = result.value(at: ["thread", "id"])?.stringValue else {
            throw CodexRuntimeError.invalidResponse("thread/start missing result.thread.id")
        }

        return threadID
    }

    public func startTurn(threadID: String, text: String) async throws -> String {
        try await start()

        let params: JSONValue = .object([
            "threadId": .string(threadID),
            "input": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text)
                ])
            ])
        ])

        let result = try await sendRequest(method: "turn/start", params: params)
        guard let turnID = result.value(at: ["turn", "id"])?.stringValue else {
            throw CodexRuntimeError.invalidResponse("turn/start missing result.turn.id")
        }

        return turnID
    }

    private func spawnProcess(executablePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task {
                await self?.handleProcessTermination(status: status)
            }
        }

        try process.run()

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.framer = JSONLFramer()

        installReadHandlers()
    }

    private func installReadHandlers() {
        guard let stdoutHandle, let stderrHandle else {
            return
        }

        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStdout(data)
            }
        }

        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStderr(data)
            }
        }
    }

    private func consumeStdout(_ data: Data) async {
        if data.isEmpty {
            return
        }

        do {
            let frames = try framer.append(data)
            for frame in frames {
                let message = try decoder.decode(JSONRPCMessageEnvelope.self, from: frame)
                try await handleIncomingMessage(message)
            }
        } catch {
            eventContinuation.yield(
                .action(
                    RuntimeAction(
                        method: "runtime/stdout/decode_error",
                        itemID: nil,
                        itemType: nil,
                        title: "Runtime stream decode error",
                        detail: error.localizedDescription
                    )
                )
            )
        }
    }

    private func consumeStderr(_ data: Data) async {
        if data.isEmpty {
            return
        }

        let message = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else {
            return
        }

        eventContinuation.yield(
            .action(
                RuntimeAction(
                    method: "runtime/stderr",
                    itemID: nil,
                    itemType: nil,
                    title: "Runtime stderr",
                    detail: message
                )
            )
        )
    }

    private func handleIncomingMessage(_ message: JSONRPCMessageEnvelope) async throws {
        if message.isResponse {
            _ = await correlator.resolveResponse(message)
            return
        }

        if message.isServerRequest {
            try await handleServerRequest(message)
            return
        }

        if let event = AppServerEventDecoder.decode(message) {
            eventContinuation.yield(event)
        }
    }

    private func handleServerRequest(_ request: JSONRPCMessageEnvelope) async throws {
        guard let id = request.id,
              let method = request.method else {
            return
        }

        if method.hasSuffix("/requestApproval") {
            try writeMessage(JSONRPCMessageEnvelope.response(id: id, result: .string("decline")))

            let action = RuntimeAction(
                method: method,
                itemID: request.params?.value(at: ["itemId"])?.stringValue,
                itemType: "approval",
                title: "Approval requested",
                detail: "Automatically declined until interactive approval UI is implemented."
            )
            eventContinuation.yield(.action(action))
            return
        }

        let error = JSONRPCResponseErrorEnvelope(
            code: -32601,
            message: "Unsupported client method: \(method)",
            data: nil
        )
        try writeMessage(JSONRPCMessageEnvelope.response(id: id, error: error))
    }

    private func performHandshake() async throws {
        let params: JSONValue = .object([
            "clientInfo": .object([
                "name": .string("codexchat_app"),
                "title": .string("CodexChat"),
                "version": .string("0.1.0")
            ])
        ])

        _ = try await sendRequest(method: "initialize", params: params, timeoutSeconds: 10)
        try sendNotification(method: "initialized", params: .object([:]))
    }

    private func sendRequest(
        method: String,
        params: JSONValue,
        timeoutSeconds: TimeInterval = 20
    ) async throws -> JSONValue {
        guard process != nil else {
            throw CodexRuntimeError.processNotRunning
        }

        let requestID = await correlator.makeRequestID()
        let request = JSONRPCRequestEnvelope(id: requestID, method: method, params: params)
        try writeMessage(request)

        let timeoutTask = Task { [correlator] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            _ = await correlator.failResponse(
                id: requestID,
                error: CodexRuntimeError.timedOut("waiting for \(method)")
            )
        }

        defer { timeoutTask.cancel() }

        let response = try await correlator.suspendResponse(id: requestID)

        if let rpcError = response.error {
            throw CodexRuntimeError.rpcError(code: rpcError.code, message: rpcError.message)
        }

        guard let result = response.result else {
            throw CodexRuntimeError.invalidResponse("Missing result payload for \(method)")
        }

        return result
    }

    private func sendNotification(method: String, params: JSONValue) throws {
        let notification = JSONRPCRequestEnvelope(id: nil, method: method, params: params)
        try writeMessage(notification)
    }

    private func writeMessage<T: Encodable>(_ payload: T) throws {
        guard let stdinHandle else {
            throw CodexRuntimeError.processNotRunning
        }

        var data = try encoder.encode(payload)
        data.append(0x0A)
        stdinHandle.write(data)
    }

    private func stopProcess() async {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        await correlator.failAll(error: CodexRuntimeError.transportClosed)
    }

    private func handleProcessTermination(status: Int32) async {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        await correlator.failAll(error: CodexRuntimeError.transportClosed)

        let action = RuntimeAction(
            method: "runtime/terminated",
            itemID: nil,
            itemType: nil,
            title: "Runtime terminated",
            detail: "codex app-server exited with status \(status)."
        )
        eventContinuation.yield(.action(action))
    }

    nonisolated public static func defaultExecutableResolver() -> String? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = envPath
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent("codex").path }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }
}
