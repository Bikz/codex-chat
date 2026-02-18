import Foundation

public extension CodexRuntime {
    func capabilities() async -> RuntimeCapabilities {
        runtimeCapabilities
    }

    func start() async throws {
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

    func restart() async throws {
        await stopProcess()
        try await start()
    }

    func stop() async {
        await stopProcess()
    }

    func startThread(
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

    func startTurn(
        threadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration? = nil,
        skillInputs: [RuntimeSkillInput] = [],
        turnOptions: RuntimeTurnOptions? = nil
    ) async throws -> String {
        try await start()

        var params = Self.makeTurnStartParams(
            threadID: threadID,
            text: text,
            safetyConfiguration: safetyConfiguration,
            skillInputs: skillInputs,
            turnOptions: turnOptions,
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
                turnOptions: turnOptions,
                includeWebSearch: false
            )
            result = try await sendRequest(method: "turn/start", params: params)
        } catch let error as CodexRuntimeError where Self.shouldRetryWithoutSkillInput(error: error) && !skillInputs.isEmpty {
            params = Self.makeTurnStartParams(
                threadID: threadID,
                text: text,
                safetyConfiguration: safetyConfiguration,
                skillInputs: [],
                turnOptions: turnOptions,
                includeWebSearch: true
            )
            result = try await sendRequest(method: "turn/start", params: params)
        }
        guard let turnID = result.value(at: ["turn", "id"])?.stringValue else {
            throw CodexRuntimeError.invalidResponse("turn/start missing result.turn.id")
        }

        return turnID
    }

    func steerTurn(
        threadID: String,
        text: String,
        turnID: String? = nil
    ) async throws {
        try await start()

        var payload: [String: JSONValue] = [
            "threadId": .string(threadID),
            "text": .string(text),
        ]
        if let turnID, !turnID.isEmpty {
            payload["turnId"] = .string(turnID)
        }

        _ = try await sendRequest(method: "turn/steer", params: .object(payload))
    }

    func readAccount(refreshToken: Bool = false) async throws -> RuntimeAccountState {
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
            name: accountObject["name"]?.stringValue ?? accountObject["fullName"]?.stringValue,
            email: accountObject["email"]?.stringValue,
            planType: accountObject["planType"]?.stringValue
        )

        return RuntimeAccountState(
            account: summary,
            authMode: Self.authMode(fromAccountType: type),
            requiresOpenAIAuth: requiresOpenAIAuth
        )
    }

    func startChatGPTLogin() async throws -> RuntimeChatGPTLoginStart {
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

    func cancelChatGPTLogin(loginID: String) async throws {
        try await start()
        _ = try await sendRequest(
            method: "account/login/cancel",
            params: .object(["loginId": .string(loginID)]),
            timeoutSeconds: 15
        )
    }

    func startAPIKeyLogin(apiKey: String) async throws {
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

    func logoutAccount() async throws {
        try await start()
        _ = try await sendRequest(method: "account/logout", params: .object([:]))
    }
}
