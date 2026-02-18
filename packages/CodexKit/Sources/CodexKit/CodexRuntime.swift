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
    private var pendingApprovalRequests: [Int: RuntimeApprovalRequest] = [:]

    private let eventStream: AsyncStream<CodexRuntimeEvent>
    private let eventContinuation: AsyncStream<CodexRuntimeEvent>.Continuation

    public init(executableResolver: @escaping ExecutableResolver = CodexRuntime.defaultExecutableResolver) {
        self.executableResolver = executableResolver

        var continuation: AsyncStream<CodexRuntimeEvent>.Continuation?
        eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(512)) { continuation = $0 }
        eventContinuation = continuation!
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

    public func startThread(
        cwd: String? = nil,
        safetyConfiguration: RuntimeSafetyConfiguration? = nil
    ) async throws -> String {
        try await start()

        var params = Self.makeThreadStartParams(
            cwd: cwd,
            safetyConfiguration: safetyConfiguration,
            includeWebSearch: true
        )
        let result: JSONValue
        do {
            result = try await sendRequest(method: "thread/start", params: params)
        } catch let error as CodexRuntimeError where Self.shouldRetryWithoutWebSearch(error: error) {
            params = Self.makeThreadStartParams(
                cwd: cwd,
                safetyConfiguration: safetyConfiguration,
                includeWebSearch: false
            )
            result = try await sendRequest(method: "thread/start", params: params)
        }
        guard let threadID = result.value(at: ["thread", "id"])?.stringValue else {
            throw CodexRuntimeError.invalidResponse("thread/start missing result.thread.id")
        }

        return threadID
    }

    public func startTurn(
        threadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration? = nil,
        skillInputs: [RuntimeSkillInput] = []
    ) async throws -> String {
        try await start()

        var params = Self.makeTurnStartParams(
            threadID: threadID,
            text: text,
            safetyConfiguration: safetyConfiguration,
            skillInputs: skillInputs,
            includeWebSearch: true
        )
        let result: JSONValue
        do {
            result = try await sendRequest(method: "turn/start", params: params)
        } catch let error as CodexRuntimeError where Self.shouldRetryWithoutWebSearch(error: error) {
            params = Self.makeTurnStartParams(
                threadID: threadID,
                text: text,
                safetyConfiguration: safetyConfiguration,
                skillInputs: skillInputs,
                includeWebSearch: false
            )
            result = try await sendRequest(method: "turn/start", params: params)
        } catch let error as CodexRuntimeError where Self.shouldRetryWithoutSkillInput(error: error) && !skillInputs.isEmpty {
            params = Self.makeTurnStartParams(
                threadID: threadID,
                text: text,
                safetyConfiguration: safetyConfiguration,
                skillInputs: [],
                includeWebSearch: true
            )
            result = try await sendRequest(method: "turn/start", params: params)
        }
        guard let turnID = result.value(at: ["turn", "id"])?.stringValue else {
            throw CodexRuntimeError.invalidResponse("turn/start missing result.turn.id")
        }

        return turnID
    }

    public func respondToApproval(
        requestID: Int,
        decision: RuntimeApprovalDecision
    ) throws {
        guard pendingApprovalRequests.removeValue(forKey: requestID) != nil else {
            throw CodexRuntimeError.invalidResponse("Unknown approval request id: \(requestID)")
        }
        try writeMessage(JSONRPCMessageEnvelope.response(id: requestID, result: decision.rpcResult))
    }

    public func readAccount(refreshToken: Bool = false) async throws -> RuntimeAccountState {
        try await start()

        let result = try await sendRequest(
            method: "account/read",
            params: .object(["refreshToken": .bool(refreshToken)])
        )

        let requiresOpenAIAuth = result.value(at: ["requiresOpenaiAuth"])?.boolValue ?? true
        guard let accountObject = result.value(at: ["account"])?.objectValue else {
            return RuntimeAccountState(
                account: nil,
                authMode: .unknown,
                requiresOpenAIAuth: requiresOpenAIAuth
            )
        }

        let type = accountObject["type"]?.stringValue ?? "unknown"
        let summary = RuntimeAccountSummary(
            type: type,
            email: accountObject["email"]?.stringValue,
            planType: accountObject["planType"]?.stringValue
        )

        return RuntimeAccountState(
            account: summary,
            authMode: Self.authMode(fromAccountType: type),
            requiresOpenAIAuth: requiresOpenAIAuth
        )
    }

    public func startChatGPTLogin() async throws -> RuntimeChatGPTLoginStart {
        try await start()

        let result = try await sendRequest(
            method: "account/login/start",
            params: .object(["type": .string("chatgpt")]),
            timeoutSeconds: 30
        )

        guard let authURLString = result.value(at: ["authUrl"])?.stringValue,
              let authURL = URL(string: authURLString)
        else {
            throw CodexRuntimeError.invalidResponse("account/login/start(chatgpt) missing authUrl")
        }

        return RuntimeChatGPTLoginStart(
            loginID: result.value(at: ["loginId"])?.stringValue,
            authURL: authURL
        )
    }

    public func startAPIKeyLogin(apiKey: String) async throws {
        try await start()
        _ = try await sendRequest(
            method: "account/login/start",
            params: .object([
                "type": .string("apiKey"),
                "apiKey": .string(apiKey),
            ]),
            timeoutSeconds: 30
        )
    }

    public func logoutAccount() async throws {
        try await start()
        _ = try await sendRequest(method: "account/logout", params: .object([:]))
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
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        framer = JSONLFramer()

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
                        threadID: nil,
                        turnID: nil,
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

        let trimmed = String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let message = trimmed, !message.isEmpty else {
            return
        }

        eventContinuation.yield(
            .action(
                RuntimeAction(
                    method: "runtime/stderr",
                    itemID: nil,
                    itemType: nil,
                    threadID: nil,
                    turnID: nil,
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

        for event in AppServerEventDecoder.decodeAll(message) {
            eventContinuation.yield(event)
        }
    }

    private func handleServerRequest(_ request: JSONRPCMessageEnvelope) async throws {
        guard let id = request.id,
              let method = request.method
        else {
            return
        }

        if method.hasSuffix("/requestApproval") {
            let approval = Self.decodeApprovalRequest(
                requestID: id,
                method: method,
                params: request.params
            )
            pendingApprovalRequests[id] = approval
            eventContinuation.yield(.approvalRequested(approval))
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
                "version": .string("0.1.0"),
            ]),
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

    private func writeMessage(_ payload: some Encodable) throws {
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
        pendingApprovalRequests.removeAll()

        await correlator.failAll(error: CodexRuntimeError.transportClosed)
    }

    private func handleProcessTermination(status: Int32) async {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        pendingApprovalRequests.removeAll()

        await correlator.failAll(error: CodexRuntimeError.transportClosed)

        let action = RuntimeAction(
            method: "runtime/terminated",
            itemID: nil,
            itemType: nil,
            threadID: nil,
            turnID: nil,
            title: "Runtime terminated",
            detail: "codex app-server exited with status \(status)."
        )
        eventContinuation.yield(.action(action))
    }

    private static func makeThreadStartParams(
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        includeWebSearch: Bool
    ) -> JSONValue {
        var params: [String: JSONValue] = [:]
        if let cwd {
            params["cwd"] = .string(cwd)
        }

        if let safetyConfiguration {
            params["approvalPolicy"] = .string(safetyConfiguration.approvalPolicy.rawValue)
            params["sandboxPolicy"] = makeSandboxPolicy(
                cwd: cwd,
                safetyConfiguration: safetyConfiguration
            )
            if includeWebSearch {
                params["webSearch"] = .string(safetyConfiguration.webSearch.rawValue)
            }
        }

        return .object(params)
    }

    private static func makeTurnStartParams(
        threadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        skillInputs: [RuntimeSkillInput],
        includeWebSearch: Bool
    ) -> JSONValue {
        var inputItems: [JSONValue] = [
            .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ]
        if !skillInputs.isEmpty {
            inputItems.append(
                contentsOf: skillInputs.map { input in
                    .object([
                        "type": .string("skill"),
                        "name": .string(input.name),
                        "path": .string(input.path),
                    ])
                }
            )
        }

        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": .array(inputItems),
        ]

        if let safetyConfiguration {
            params["approvalPolicy"] = .string(safetyConfiguration.approvalPolicy.rawValue)
            params["sandboxPolicy"] = makeSandboxPolicy(
                cwd: nil,
                safetyConfiguration: safetyConfiguration
            )
            if includeWebSearch {
                params["webSearch"] = .string(safetyConfiguration.webSearch.rawValue)
            }
        }

        return .object(params)
    }

    private static func makeSandboxPolicy(
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration
    ) -> JSONValue {
        switch safetyConfiguration.sandboxMode {
        case .readOnly:
            return .object(["type": .string(RuntimeSandboxMode.readOnly.rawValue)])
        case .workspaceWrite:
            var roots = safetyConfiguration.writableRoots
            if roots.isEmpty, let cwd {
                roots = [cwd]
            }
            return .object([
                "type": .string(RuntimeSandboxMode.workspaceWrite.rawValue),
                "writableRoots": .array(roots.map(JSONValue.string)),
                "networkAccess": .bool(safetyConfiguration.networkAccess),
            ])
        case .dangerFullAccess:
            return .object(["type": .string(RuntimeSandboxMode.dangerFullAccess.rawValue)])
        }
    }

    private static func shouldRetryWithoutWebSearch(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        return (lowered.contains("websearch") || lowered.contains("web_search"))
            && (lowered.contains("unknown") || lowered.contains("invalid"))
    }

    private static func shouldRetryWithoutSkillInput(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        return lowered.contains("skill")
            && (lowered.contains("unknown") || lowered.contains("invalid"))
    }

    private static func decodeApprovalRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimeApprovalRequest {
        let payload = params ?? .object([:])
        let kind: RuntimeApprovalKind = if method.contains("commandExecution") {
            .commandExecution
        } else if method.contains("fileChange") {
            .fileChange
        } else {
            .unknown
        }

        let command: [String] = if let array = payload.value(at: ["command"])?.arrayValue {
            array.compactMap(\.stringValue)
        } else if let parsed = payload.value(at: ["parsedCmd"])?.arrayValue {
            parsed.compactMap(\.stringValue)
        } else if let single = payload.value(at: ["command"])?.stringValue {
            [single]
        } else {
            []
        }

        let changes: [RuntimeFileChange] = (payload.value(at: ["changes"])?.arrayValue ?? []).compactMap { change in
            guard let path = change.value(at: ["path"])?.stringValue else {
                return nil
            }
            let kind = change.value(at: ["kind"])?.stringValue ?? "update"
            let diff = change.value(at: ["diff"])?.stringValue
            return RuntimeFileChange(path: path, kind: kind, diff: diff)
        }

        return RuntimeApprovalRequest(
            id: requestID,
            kind: kind,
            method: method,
            threadID: payload.value(at: ["threadId"])?.stringValue,
            turnID: payload.value(at: ["turnId"])?.stringValue,
            itemID: payload.value(at: ["itemId"])?.stringValue,
            reason: payload.value(at: ["reason"])?.stringValue,
            risk: payload.value(at: ["risk"])?.stringValue,
            cwd: payload.value(at: ["cwd"])?.stringValue,
            command: command,
            changes: changes,
            detail: payload.prettyPrinted()
        )
    }

    public nonisolated static func defaultExecutableResolver() -> String? {
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

    public nonisolated static func launchDeviceAuthInTerminal() throws {
        guard defaultExecutableResolver() != nil else {
            throw CodexRuntimeError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to do script \"codex login --device-auth\"",
            "-e", "tell application \"Terminal\" to activate",
        ]
        try process.run()
    }

    private nonisolated static func authMode(fromAccountType type: String) -> RuntimeAuthMode {
        switch type.lowercased() {
        case "apikey":
            .apiKey
        case "chatgpt":
            .chatGPT
        case "chatgptauthtokens":
            .chatGPTAuthTokens
        default:
            .unknown
        }
    }
}
