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
    private let shouldScopeRuntimeIDs: Bool
    private var workersByID: [RuntimePoolWorkerID: CodexRuntimeWorker]
    private var eventPumpTasksByWorkerID: [RuntimePoolWorkerID: Task<Void, Never>] = [:]
    private var routeBySyntheticApprovalID: [Int: ApprovalRoute] = [:]
    private var nextSyntheticApprovalID: Int = 1
    private var pinnedWorkerIDByLocalThreadID: [UUID: RuntimePoolWorkerID] = [:]

    private let unifiedEventStream: AsyncStream<CodexRuntimeEvent>
    private let unifiedEventContinuation: AsyncStream<CodexRuntimeEvent>.Continuation

    init(primaryRuntime: CodexRuntime, configuredWorkerCount: Int) {
        self.configuredWorkerCount = max(1, configuredWorkerCount)
        shouldScopeRuntimeIDs = self.configuredWorkerCount > 1
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

    func pin(localThreadID: UUID, runtimeThreadID: String) {
        if let (workerID, _) = Self.parseScopedID(runtimeThreadID) {
            pinnedWorkerIDByLocalThreadID[localThreadID] = workerID
            return
        }

        pinnedWorkerIDByLocalThreadID[localThreadID] = Constants.primaryWorkerID
    }

    func unpin(localThreadID: UUID) {
        pinnedWorkerIDByLocalThreadID.removeValue(forKey: localThreadID)
    }

    func resetPins() {
        pinnedWorkerIDByLocalThreadID.removeAll(keepingCapacity: false)
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
        return scopeIfNeeded(id: rawThreadID, workerID: workerID)
    }

    func startTurn(
        scopedThreadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        skillInputs: [RuntimeSkillInput],
        inputItems: [RuntimeInputItem],
        turnOptions: RuntimeTurnOptions?
    ) async throws -> String {
        let route = Self.resolveRoute(fromPossiblyScopedThreadID: scopedThreadID)
        let worker = try await worker(for: route.workerID)
        let rawTurnID = try await worker.startTurn(
            threadID: route.threadID,
            text: text,
            safetyConfiguration: safetyConfiguration,
            skillInputs: skillInputs,
            inputItems: inputItems,
            turnOptions: turnOptions
        )
        return scopeIfNeeded(id: rawTurnID, workerID: route.workerID)
    }

    func steerTurn(
        scopedThreadID: String,
        text: String,
        expectedTurnID scopedTurnID: String
    ) async throws {
        let route = Self.resolveRoute(fromPossiblyScopedThreadID: scopedThreadID)
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
        if !shouldScopeRuntimeIDs {
            try await primaryWorker().respondToApproval(requestID: requestID, decision: decision)
            return
        }

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
            pinnedThreadCount: pinnedWorkerIDByLocalThreadID.count,
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
        if let pinnedWorkerID = pinnedWorkerIDByLocalThreadID[localThreadID],
           workersByID[pinnedWorkerID] != nil
        {
            return pinnedWorkerID
        }

        let selectedWorkerID = Self.consistentWorkerID(
            for: localThreadID,
            workerCount: configuredWorkerCount
        )
        let resolvedWorkerID = workersByID[selectedWorkerID] == nil
            ? Constants.primaryWorkerID
            : selectedWorkerID
        pinnedWorkerIDByLocalThreadID[localThreadID] = resolvedWorkerID
        return resolvedWorkerID
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
            return .threadStarted(threadID: scopeIfNeeded(id: threadID, workerID: workerID))

        case let .turnStarted(threadID, turnID):
            return .turnStarted(
                threadID: threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                turnID: scopeIfNeeded(id: turnID, workerID: workerID)
            )

        case let .assistantMessageDelta(threadID, turnID, itemID, delta):
            return .assistantMessageDelta(
                threadID: threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                turnID: turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                itemID: scopeIfNeeded(id: itemID, workerID: workerID),
                delta: delta
            )

        case let .commandOutputDelta(output):
            return .commandOutputDelta(
                RuntimeCommandOutputDelta(
                    itemID: scopeIfNeeded(id: output.itemID, workerID: workerID),
                    threadID: output.threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    turnID: output.turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    delta: output.delta
                )
            )

        case let .followUpSuggestions(batch):
            return .followUpSuggestions(
                RuntimeFollowUpSuggestionBatch(
                    threadID: batch.threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    turnID: batch.turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    suggestions: batch.suggestions
                )
            )

        case let .fileChangesUpdated(update):
            return .fileChangesUpdated(
                RuntimeFileChangeUpdate(
                    itemID: update.itemID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    threadID: update.threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    turnID: update.turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    status: update.status,
                    changes: update.changes
                )
            )

        case let .approvalRequested(request):
            let requestID: Int
            if shouldScopeRuntimeIDs {
                let syntheticID = nextSyntheticApprovalID
                nextSyntheticApprovalID = nextSyntheticApprovalID &+ 1
                routeBySyntheticApprovalID[syntheticID] = ApprovalRoute(
                    workerID: workerID,
                    rawRequestID: request.id
                )
                requestID = syntheticID
            } else {
                requestID = request.id
            }
            return .approvalRequested(
                RuntimeApprovalRequest(
                    id: requestID,
                    kind: request.kind,
                    method: request.method,
                    threadID: request.threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    turnID: request.turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    itemID: request.itemID.map { scopeIfNeeded(id: $0, workerID: workerID) },
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
                    itemID: action.itemID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    itemType: action.itemType,
                    threadID: action.threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    turnID: action.turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    title: action.title,
                    detail: action.detail,
                    workerTrace: action.workerTrace
                )
            )

        case let .turnCompleted(completion):
            return .turnCompleted(
                RuntimeTurnCompletion(
                    threadID: completion.threadID.map { scopeIfNeeded(id: $0, workerID: workerID) },
                    turnID: completion.turnID.map { scopeIfNeeded(id: $0, workerID: workerID) },
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

    static func resolveRoute(fromPossiblyScopedThreadID scopedThreadID: String) -> TurnRoute {
        guard let (workerID, rawThreadID) = parseScopedID(scopedThreadID),
              !rawThreadID.isEmpty
        else {
            // Backward compatibility with existing persisted mappings created pre-pool.
            return TurnRoute(
                workerID: Constants.primaryWorkerID,
                threadID: scopedThreadID
            )
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

    static func consistentWorkerID(
        for localThreadID: UUID,
        workerCount: Int
    ) -> RuntimePoolWorkerID {
        guard workerCount > 1 else {
            return Constants.primaryWorkerID
        }

        let hash = deterministicHash(for: localThreadID)
        let slot = Int(hash % UInt64(workerCount))
        return RuntimePoolWorkerID(slot)
    }

    static func unscopedID(_ possiblyScopedID: String) -> String {
        if let (_, rawID) = parseScopedID(possiblyScopedID) {
            return rawID
        }
        return possiblyScopedID
    }

    private func scopeIfNeeded(id: String, workerID: RuntimePoolWorkerID) -> String {
        guard shouldScopeRuntimeIDs else {
            return id
        }
        return Self.scope(id: id, workerID: workerID)
    }

    private static func deterministicHash(for localThreadID: UUID) -> UInt64 {
        let bytes = withUnsafeBytes(of: localThreadID.uuid) { buffer in
            Array(buffer)
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
