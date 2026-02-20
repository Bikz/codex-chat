import CodexKit
import Foundation

struct RuntimePoolWorkerEvent: Sendable {
    let workerID: RuntimePoolWorkerID
    let event: CodexRuntimeEvent
}

actor CodexRuntimeWorker {
    let workerID: RuntimePoolWorkerID
    private let runtime: CodexRuntime

    private let eventStream: AsyncStream<RuntimePoolWorkerEvent>
    private let eventContinuation: AsyncStream<RuntimePoolWorkerEvent>.Continuation
    private var eventPumpTask: Task<Void, Never>?

    init(workerID: RuntimePoolWorkerID, runtime: CodexRuntime) {
        self.workerID = workerID
        self.runtime = runtime

        var continuation: AsyncStream<RuntimePoolWorkerEvent>.Continuation?
        eventStream = AsyncStream<RuntimePoolWorkerEvent>(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        eventContinuation = continuation!
    }

    deinit {
        eventPumpTask?.cancel()
        eventContinuation.finish()
    }

    func events() -> AsyncStream<RuntimePoolWorkerEvent> {
        eventStream
    }

    func start() async throws {
        try await runtime.start()
        startEventPumpIfNeeded()
    }

    func restart() async throws {
        try await runtime.restart()
        startEventPumpIfNeeded()
    }

    func stop() async {
        eventPumpTask?.cancel()
        eventPumpTask = nil
        await runtime.stop()
    }

    func capabilities() async -> RuntimeCapabilities {
        await runtime.capabilities()
    }

    func startThread(
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration?
    ) async throws -> String {
        try await runtime.startThread(
            cwd: cwd,
            safetyConfiguration: safetyConfiguration
        )
    }

    func startTurn(
        threadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        skillInputs: [RuntimeSkillInput],
        inputItems: [RuntimeInputItem],
        turnOptions: RuntimeTurnOptions?
    ) async throws -> String {
        try await runtime.startTurn(
            threadID: threadID,
            text: text,
            safetyConfiguration: safetyConfiguration,
            skillInputs: skillInputs,
            inputItems: inputItems,
            turnOptions: turnOptions
        )
    }

    func steerTurn(
        threadID: String,
        text: String,
        expectedTurnID: String
    ) async throws {
        try await runtime.steerTurn(
            threadID: threadID,
            text: text,
            expectedTurnID: expectedTurnID
        )
    }

    func respondToApproval(
        requestID: Int,
        decision: RuntimeApprovalDecision
    ) async throws {
        try await runtime.respondToApproval(
            requestID: requestID,
            decision: decision
        )
    }

    func readAccount(refreshToken: Bool) async throws -> RuntimeAccountState {
        try await runtime.readAccount(refreshToken: refreshToken)
    }

    func startChatGPTLogin() async throws -> RuntimeChatGPTLoginStart {
        try await runtime.startChatGPTLogin()
    }

    func cancelChatGPTLogin(loginID: String) async throws {
        try await runtime.cancelChatGPTLogin(loginID: loginID)
    }

    func startAPIKeyLogin(apiKey: String) async throws {
        try await runtime.startAPIKeyLogin(apiKey: apiKey)
    }

    func logoutAccount() async throws {
        try await runtime.logoutAccount()
    }

    func listAllModels() async throws -> [RuntimeModelInfo] {
        try await runtime.listAllModels()
    }

    func makeSiblingRuntime() async -> CodexRuntime {
        await runtime.makeSiblingRuntime()
    }

    private func startEventPumpIfNeeded() {
        guard eventPumpTask == nil else {
            return
        }

        eventPumpTask = Task { [workerID] in
            let runtimeEvents = await runtime.events()
            for await event in runtimeEvents {
                guard !Task.isCancelled else {
                    break
                }
                eventContinuation.yield(
                    RuntimePoolWorkerEvent(workerID: workerID, event: event)
                )
            }
        }
    }
}
