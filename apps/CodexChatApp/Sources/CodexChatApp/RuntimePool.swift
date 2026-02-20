import CodexKit
import Foundation

actor RuntimePool {
    private enum Constants {
        static let scopedDelimiter = "|"
        static let primaryWorkerID = RuntimePoolWorkerID(0)
    }

    struct TurnRoute: Hashable, Sendable {
        let workerID: RuntimePoolWorkerID
        let threadID: String
    }

    private struct ApprovalRoute: Sendable {
        let workerID: RuntimePoolWorkerID
        let rawRequestID: Int
    }

    private let configuredWorkerCount: Int
    private var workersByID: [RuntimePoolWorkerID: CodexRuntimeWorker]
    private var eventPumpTasksByWorkerID: [RuntimePoolWorkerID: Task<Void, Never>] = [:]
    private var routeBySyntheticApprovalID: [Int: ApprovalRoute] = [:]
    private var nextSyntheticApprovalID: Int = 1

    private let unifiedEventStream: AsyncStream<CodexRuntimeEvent>
    private let unifiedEventContinuation: AsyncStream<CodexRuntimeEvent>.Continuation

    init(primaryRuntime: CodexRuntime, configuredWorkerCount: Int) {
        self.configuredWorkerCount = max(1, configuredWorkerCount)
        workersByID = [
            Constants.primaryWorkerID: CodexRuntimeWorker(
                workerID: Constants.primaryWorkerID,
                runtime: primaryRuntime
            ),
        ]

        var continuation: AsyncStream<CodexRuntimeEvent>.Continuation?
        unifiedEventStream = AsyncStream<CodexRuntimeEvent>(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        unifiedEventContinuation = continuation!
    }

    deinit {
        for task in eventPumpTasksByWorkerID.values {
            task.cancel()
        }
        unifiedEventContinuation.finish()
    }

    func configuredSize() -> Int {
        configuredWorkerCount
    }

    func events() -> AsyncStream<CodexRuntimeEvent> {
        unifiedEventStream
    }

    func start() async throws {
        try await ensureWorkersInitialized()

        for workerID in workersByID.keys.sorted() {
            guard let worker = workersByID[workerID] else { continue }
            try await worker.start()
            startEventPumpIfNeeded(for: workerID)
        }
    }

    func restart() async throws {
        try await ensureWorkersInitialized()

        for workerID in workersByID.keys.sorted() {
            guard let worker = workersByID[workerID] else { continue }
            try await worker.restart()
            startEventPumpIfNeeded(for: workerID)
        }
    }

    func stop() async {
        for task in eventPumpTasksByWorkerID.values {
            task.cancel()
        }
        eventPumpTasksByWorkerID.removeAll(keepingCapacity: false)

        for worker in workersByID.values {
            await worker.stop()
        }

        routeBySyntheticApprovalID.removeAll(keepingCapacity: false)
    }

    func capabilities() async -> RuntimeCapabilities {
        guard let primaryWorker = workersByID[Constants.primaryWorkerID] else {
            return .none
        }
        return await primaryWorker.capabilities()
    }

    func readAccount(refreshToken: Bool) async throws -> RuntimeAccountState {
        try await primaryWorker().readAccount(refreshToken: refreshToken)
    }

    func startChatGPTLogin() async throws -> RuntimeChatGPTLoginStart {
        try await primaryWorker().startChatGPTLogin()
    }

    func cancelChatGPTLogin(loginID: String) async throws {
        try await primaryWorker().cancelChatGPTLogin(loginID: loginID)
    }

    func startAPIKeyLogin(apiKey: String) async throws {
        try await primaryWorker().startAPIKeyLogin(apiKey: apiKey)
    }

    func logoutAccount() async throws {
        try await primaryWorker().logoutAccount()
    }

    func listAllModels() async throws -> [RuntimeModelInfo] {
        try await primaryWorker().listAllModels()
    }

    func startThread(
        localThreadID: UUID,
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration?
    ) async throws -> String {
        let workerID = workerID(for: localThreadID)
        let worker = try await worker(for: workerID)
        let rawThreadID = try await worker.startThread(
            cwd: cwd,
            safetyConfiguration: safetyConfiguration
        )
        return Self.scope(id: rawThreadID, workerID: workerID)
    }

    func startTurn(
        scopedThreadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        skillInputs: [RuntimeSkillInput],
        inputItems: [RuntimeInputItem],
        turnOptions: RuntimeTurnOptions?
    ) async throws -> String {
        let route = try Self.resolveRoute(fromScopedThreadID: scopedThreadID)
        let worker = try await worker(for: route.workerID)
        let rawTurnID = try await worker.startTurn(
            threadID: route.threadID,
            text: text,
            safetyConfiguration: safetyConfiguration,
            skillInputs: skillInputs,
            inputItems: inputItems,
            turnOptions: turnOptions
        )
        return Self.scope(id: rawTurnID, workerID: route.workerID)
    }

    func steerTurn(
        scopedThreadID: String,
        text: String,
        expectedTurnID scopedTurnID: String
    ) async throws {
        let route = try Self.resolveRoute(fromScopedThreadID: scopedThreadID)
        let rawTurnID = Self.unscopedID(scopedTurnID)
        let worker = try await worker(for: route.workerID)
        try await worker.steerTurn(
            threadID: route.threadID,
            text: text,
            expectedTurnID: rawTurnID
        )
    }

    func respondToApproval(
        requestID: Int,
        decision: RuntimeApprovalDecision
    ) async throws {
        guard let route = routeBySyntheticApprovalID.removeValue(forKey: requestID) else {
            throw CodexRuntimeError.invalidResponse("Unknown pooled approval request id: \(requestID)")
        }
        let worker = try await worker(for: route.workerID)
        try await worker.respondToApproval(requestID: route.rawRequestID, decision: decision)
    }

    func snapshot() -> RuntimePoolSnapshot {
        let workerIDs = workersByID.keys.sorted()
        let metrics = workerIDs.map {
            RuntimePoolWorkerMetrics(
                workerID: $0,
                health: .healthy
            )
        }

        return RuntimePoolSnapshot(
            configuredWorkerCount: configuredWorkerCount,
            activeWorkerCount: workersByID.count,
            pinnedThreadCount: 0,
            totalQueuedTurns: 0,
            totalInFlightTurns: 0,
            workers: metrics
        )
    }

    private func ensureWorkersInitialized() async throws {
        guard workersByID.count < configuredWorkerCount else {
            return
        }

        guard let primaryWorker = workersByID[Constants.primaryWorkerID] else {
            throw CodexRuntimeError.processNotRunning
        }

        for rawIndex in 1 ..< configuredWorkerCount {
            let workerID = RuntimePoolWorkerID(rawIndex)
            if workersByID[workerID] != nil {
                continue
            }

            let siblingRuntime = await primaryWorker.makeSiblingRuntime()
            workersByID[workerID] = CodexRuntimeWorker(workerID: workerID, runtime: siblingRuntime)
        }
    }

    private func primaryWorker() throws -> CodexRuntimeWorker {
        guard let worker = workersByID[Constants.primaryWorkerID] else {
            throw CodexRuntimeError.processNotRunning
        }
        return worker
    }

    private func worker(for workerID: RuntimePoolWorkerID) async throws -> CodexRuntimeWorker {
        try await ensureWorkersInitialized()
        guard let worker = workersByID[workerID] else {
            throw CodexRuntimeError.processNotRunning
        }
        return worker
    }

    private func workerID(for localThreadID: UUID) -> RuntimePoolWorkerID {
        guard configuredWorkerCount > 1 else {
            return Constants.primaryWorkerID
        }

        var hasher = Hasher()
        hasher.combine(localThreadID)
        let hashValue = hasher.finalize()
        let slot = (hashValue & Int.max) % configuredWorkerCount
        return RuntimePoolWorkerID(slot)
    }

    private func startEventPumpIfNeeded(for workerID: RuntimePoolWorkerID) {
        guard eventPumpTasksByWorkerID[workerID] == nil,
              let worker = workersByID[workerID]
        else {
            return
        }

        let streamTask = Task.detached { [worker] in
            await worker.events()
        }

        eventPumpTasksByWorkerID[workerID] = Task { [weak self] in
            let events = await streamTask.value
            for await envelope in events {
                guard !Task.isCancelled else {
                    break
                }
                await self?.emit(envelope)
            }
        }
    }

    private func emit(_ envelope: RuntimePoolWorkerEvent) {
        let workerID = envelope.workerID
        let transformed = transformEvent(envelope.event, workerID: workerID)
        unifiedEventContinuation.yield(transformed)
    }

    private func transformEvent(
        _ event: CodexRuntimeEvent,
        workerID: RuntimePoolWorkerID
    ) -> CodexRuntimeEvent {
        switch event {
        case let .threadStarted(threadID):
            return .threadStarted(threadID: Self.scope(id: threadID, workerID: workerID))

        case let .turnStarted(threadID, turnID):
            return .turnStarted(
                threadID: threadID.map { Self.scope(id: $0, workerID: workerID) },
                turnID: Self.scope(id: turnID, workerID: workerID)
            )

        case let .assistantMessageDelta(threadID, turnID, itemID, delta):
            return .assistantMessageDelta(
                threadID: threadID.map { Self.scope(id: $0, workerID: workerID) },
                turnID: turnID.map { Self.scope(id: $0, workerID: workerID) },
                itemID: Self.scope(id: itemID, workerID: workerID),
                delta: delta
            )

        case let .commandOutputDelta(output):
            return .commandOutputDelta(
                RuntimeCommandOutputDelta(
                    itemID: Self.scope(id: output.itemID, workerID: workerID),
                    threadID: output.threadID.map { Self.scope(id: $0, workerID: workerID) },
                    turnID: output.turnID.map { Self.scope(id: $0, workerID: workerID) },
                    delta: output.delta
                )
            )

        case let .followUpSuggestions(batch):
            return .followUpSuggestions(
                RuntimeFollowUpSuggestionBatch(
                    threadID: batch.threadID.map { Self.scope(id: $0, workerID: workerID) },
                    turnID: batch.turnID.map { Self.scope(id: $0, workerID: workerID) },
                    suggestions: batch.suggestions
                )
            )

        case let .fileChangesUpdated(update):
            return .fileChangesUpdated(
                RuntimeFileChangeUpdate(
                    itemID: update.itemID.map { Self.scope(id: $0, workerID: workerID) },
                    threadID: update.threadID.map { Self.scope(id: $0, workerID: workerID) },
                    turnID: update.turnID.map { Self.scope(id: $0, workerID: workerID) },
                    status: update.status,
                    changes: update.changes
                )
            )

        case let .approvalRequested(request):
            let syntheticID = nextSyntheticApprovalID
            nextSyntheticApprovalID = nextSyntheticApprovalID &+ 1
            routeBySyntheticApprovalID[syntheticID] = ApprovalRoute(
                workerID: workerID,
                rawRequestID: request.id
            )
            return .approvalRequested(
                RuntimeApprovalRequest(
                    id: syntheticID,
                    kind: request.kind,
                    method: request.method,
                    threadID: request.threadID.map { Self.scope(id: $0, workerID: workerID) },
                    turnID: request.turnID.map { Self.scope(id: $0, workerID: workerID) },
                    itemID: request.itemID.map { Self.scope(id: $0, workerID: workerID) },
                    reason: request.reason,
                    risk: request.risk,
                    cwd: request.cwd,
                    command: request.command,
                    changes: request.changes,
                    detail: request.detail
                )
            )

        case let .action(action):
            return .action(
                RuntimeAction(
                    method: action.method,
                    itemID: action.itemID.map { Self.scope(id: $0, workerID: workerID) },
                    itemType: action.itemType,
                    threadID: action.threadID.map { Self.scope(id: $0, workerID: workerID) },
                    turnID: action.turnID.map { Self.scope(id: $0, workerID: workerID) },
                    title: action.title,
                    detail: action.detail,
                    workerTrace: action.workerTrace
                )
            )

        case let .turnCompleted(completion):
            return .turnCompleted(
                RuntimeTurnCompletion(
                    threadID: completion.threadID.map { Self.scope(id: $0, workerID: workerID) },
                    turnID: completion.turnID.map { Self.scope(id: $0, workerID: workerID) },
                    status: completion.status,
                    errorMessage: completion.errorMessage
                )
            )

        case .accountUpdated, .accountLoginCompleted:
            return event
        }
    }

    static func resolveRoute(fromScopedThreadID scopedThreadID: String) throws -> TurnRoute {
        guard let (workerID, rawThreadID) = parseScopedID(scopedThreadID),
              !rawThreadID.isEmpty
        else {
            throw CodexRuntimeError.invalidResponse("Invalid scoped runtime thread id: \(scopedThreadID)")
        }

        return TurnRoute(workerID: workerID, threadID: rawThreadID)
    }

    static func parseScopedID(_ scopedID: String) -> (RuntimePoolWorkerID, String)? {
        guard let delimiterRange = scopedID.range(of: Constants.scopedDelimiter),
              scopedID.hasPrefix("w")
        else {
            return nil
        }

        let workerPart = String(scopedID[..<delimiterRange.lowerBound])
        let rawPart = String(scopedID[delimiterRange.upperBound...])
        guard let parsedWorker = Int(workerPart.dropFirst()) else {
            return nil
        }

        return (RuntimePoolWorkerID(parsedWorker), rawPart)
    }

    static func scope(id rawID: String, workerID: RuntimePoolWorkerID) -> String {
        "\(workerID.description)\(Constants.scopedDelimiter)\(rawID)"
    }

    static func unscopedID(_ possiblyScopedID: String) -> String {
        if let (_, rawID) = parseScopedID(possiblyScopedID) {
            return rawID
        }
        return possiblyScopedID
    }
}
