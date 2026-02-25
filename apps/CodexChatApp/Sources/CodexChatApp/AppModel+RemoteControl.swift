import AppKit
import CodexChatCore
import CodexChatRemoteControl
import CodexKit
import Foundation

private struct RemoteRelayControlSignal: Decodable {
    let type: String
    let sessionID: String?
    let connectedDeviceCount: Int?
    let requestID: String?
    let requesterIP: String?
    let requestedAt: Date?
    let expiresAt: Date?
    let approved: Bool?
    let reason: String?
    let lastSeq: UInt64?
}

private enum RemoteControlSnapshotReason: String {
    case websocketAuthenticated = "websocket_authenticated"
    case snapshotRequest = "snapshot_request"
    case stateChanged = "state_changed"
    case commandApplied = "command_applied"
    case sequenceGap = "sequence_gap"
}

extension AppModel {
    private static let defaultRemoteControlJoinURL = "https://remote.codexchat.app/rc"
    private static let defaultRemoteControlRelayWSURL = "wss://remote.codexchat.app/ws"
    private static let remoteControlSnapshotPumpNanoseconds: UInt64 = 700_000_000
    private static let remoteControlSnapshotMessageLimit = 160

    var isRemoteControlSessionActive: Bool {
        remoteControlStatus.phase == .active && remoteControlStatus.session != nil
    }

    var remoteControlJoinURL: URL? {
        remoteControlStatus.session?.joinURL
    }

    var remoteControlConnectedDeviceLabel: String {
        Self.remoteControlConnectedDeviceLabel(count: remoteControlStatus.connectedDeviceCount)
    }

    static func remoteControlConnectedDeviceLabel(count: Int) -> String {
        let sanitizedCount = max(0, count)
        let suffix = sanitizedCount == 1 ? "device" : "devices"
        return "\(sanitizedCount) \(suffix) connected"
    }

    func presentRemoteControlSheet() {
        isRemoteControlSheetVisible = true
        Task {
            await refreshRemoteControlStatus()
        }
    }

    func dismissRemoteControlSheet() {
        isRemoteControlSheetVisible = false
    }

    func startRemoteControlSession() {
        guard let urls = resolvedRemoteControlURLs() else {
            return
        }

        remoteControlStatusMessage = "Starting remote session..."
        Task { [weak self] in
            guard let self else { return }
            do {
                closeRemoteControlWebSocket(reason: "Starting new session")
                let descriptor = try await remoteControlBroker.startSession(
                    joinBaseURL: urls.joinURL,
                    relayWebSocketURL: urls.relayWebSocketURL
                )

                await refreshRemoteControlStatus()
                remoteControlReconnectAttempt = 0
                remoteControlInboundSequenceTracker.reset()
                remoteControlInboundSequenceTrackersByConnectionID = [:]
                remoteControlOutboundSequence = 0
                remoteControlLastSnapshotSignature = nil
                remoteControlLastEventEntryIDsByThreadID = [:]
                remoteControlLastTurnStateByThreadID = [:]
                remoteControlLastPendingApprovalRequestIDs = []

                startRemoteControlWebSocket(using: descriptor)
                remoteControlStatusMessage = "Remote session started. Join token expires at \(Self.remoteTimestamp(descriptor.joinTokenLease.expiresAt))."
                appendLog(.info, "Remote control session started: \(descriptor.sessionID)")
            } catch {
                await refreshRemoteControlStatus()
                remoteControlStatusMessage = "Unable to start remote session: \(error.localizedDescription)"
                appendLog(.error, "Failed to start remote control session: \(error.localizedDescription)")
            }
        }
    }

    func stopRemoteControlSession() {
        Task { [weak self] in
            guard let self else { return }
            closeRemoteControlWebSocket(reason: "Stopped by user")
            await remoteControlBroker.stopSession(reason: "Stopped by user")
            await refreshRemoteControlStatus()
            remoteControlStatusMessage = "Remote session stopped."
            appendLog(.info, "Remote control session stopped by user")
        }
    }

    func copyRemoteControlJoinLink() {
        guard let joinURL = remoteControlJoinURL else {
            remoteControlStatusMessage = "Start a remote session first to generate a QR link."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joinURL.absoluteString, forType: .string)
        remoteControlStatusMessage = "Copied remote link to clipboard."
    }

    func refreshRemoteControlStatus() async {
        remoteControlStatus = await remoteControlBroker.currentStatus()
    }

    func updateRemoteControlConnectedDeviceCount(_ count: Int) {
        Task { [weak self] in
            guard let self else { return }
            await remoteControlBroker.updateConnectedDeviceCount(count)
            await refreshRemoteControlStatus()
        }
    }

    func handleRemoteApprovalCapabilityChange() async {
        guard isRemoteControlSessionActive else {
            return
        }
        await sendRemoteControlHello()
        await sendRemoteControlSnapshot(reason: .stateChanged, force: true)
    }

    private func resolvedRemoteControlURLs() -> (joinURL: URL, relayWebSocketURL: URL)? {
        let joinRaw = ProcessInfo.processInfo.environment["CODEXCHAT_REMOTE_CONTROL_JOIN_URL"]
            ?? Self.defaultRemoteControlJoinURL
        let relayRaw = ProcessInfo.processInfo.environment["CODEXCHAT_REMOTE_CONTROL_RELAY_WS_URL"]
            ?? Self.defaultRemoteControlRelayWSURL

        guard let joinURL = URL(string: joinRaw) else {
            remoteControlStatusMessage = "Invalid CODEXCHAT_REMOTE_CONTROL_JOIN_URL: \(joinRaw)"
            return nil
        }
        guard let relayWebSocketURL = URL(string: relayRaw) else {
            remoteControlStatusMessage = "Invalid CODEXCHAT_REMOTE_CONTROL_RELAY_WS_URL: \(relayRaw)"
            return nil
        }
        return (joinURL, relayWebSocketURL)
    }

    private func startRemoteControlWebSocket(using descriptor: RemoteControlSessionDescriptor) {
        guard let socketURL = remoteControlDesktopSocketURL(from: descriptor) else {
            remoteControlStatusMessage = "Unable to build relay websocket URL."
            return
        }

        closeRemoteControlWebSocket(reason: "Reconnecting websocket")
        remoteControlWebSocketAuthToken = descriptor.desktopSessionToken
        remoteControlRelayAuthenticated = false

        let websocketTask = URLSession.shared.webSocketTask(with: socketURL)
        remoteControlWebSocketTask = websocketTask
        websocketTask.resume()

        remoteControlStatusMessage = "Connecting to remote relay..."
        startRemoteControlReceiveLoop()
        startRemoteControlSnapshotPump()
        Task { [weak self] in
            await self?.sendRemoteControlAuthSignalIfNeeded()
        }
    }

    private func closeRemoteControlWebSocket(reason: String) {
        remoteControlReceiveTask?.cancel()
        remoteControlReceiveTask = nil
        remoteControlSnapshotPumpTask?.cancel()
        remoteControlSnapshotPumpTask = nil
        remoteControlReconnectTask?.cancel()
        remoteControlReconnectTask = nil
        remoteControlWebSocketTask?.cancel(with: .normalClosure, reason: nil)
        remoteControlWebSocketTask = nil
        remoteControlWebSocketAuthToken = nil
        remoteControlRelayAuthenticated = false
        remoteControlPendingPairRequest = nil
        remoteControlInboundSequenceTrackersByConnectionID = [:]
        remoteControlLastSnapshotSignature = nil
        remoteControlLastEventEntryIDsByThreadID = [:]
        remoteControlLastTurnStateByThreadID = [:]
        remoteControlLastPendingApprovalRequestIDs = []
        appendLog(.debug, "Remote control websocket closed: \(reason)")
    }

    private func remoteControlDesktopSocketURL(from descriptor: RemoteControlSessionDescriptor) -> URL? {
        guard var components = URLComponents(url: descriptor.relayWebSocketURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll(where: { $0.name == "token" })
        components.queryItems = queryItems
        return components.url
    }

    private func startRemoteControlReceiveLoop() {
        remoteControlReceiveTask?.cancel()

        guard let websocketTask = remoteControlWebSocketTask else {
            return
        }

        remoteControlReceiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await websocketTask.receive()
                    await handleRemoteControlWebSocketMessage(message)
                } catch {
                    handleRemoteControlWebSocketDisconnect(error)
                    return
                }
            }
        }
    }

    private func handleRemoteControlWebSocketDisconnect(_ error: Error) {
        remoteControlReceiveTask?.cancel()
        remoteControlReceiveTask = nil

        guard remoteControlWebSocketTask != nil else {
            return
        }

        guard isRemoteControlSessionActive else {
            remoteControlStatusMessage = "Remote session disconnected."
            return
        }

        remoteControlStatusMessage = "Remote relay disconnected: \(error.localizedDescription)"
        scheduleRemoteControlReconnectIfNeeded()
    }

    private func scheduleRemoteControlReconnectIfNeeded() {
        guard remoteControlReconnectTask == nil else {
            return
        }

        remoteControlReconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let exponent = min(max(remoteControlReconnectAttempt, 0), 4)
            let delaySeconds = min(15, 1 << exponent)
            remoteControlReconnectAttempt = remoteControlReconnectAttempt &+ 1
            remoteControlStatusMessage = "Remote relay disconnected. Reconnecting in \(delaySeconds)s..."

            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            remoteControlReconnectTask = nil
            await refreshRemoteControlStatus()

            guard let session = remoteControlStatus.session else {
                return
            }
            startRemoteControlWebSocket(using: session)
        }
    }

    private func handleRemoteControlWebSocketMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case let .string(raw):
            await handleRemoteControlIncomingData(Data(raw.utf8))
        case let .data(data):
            await handleRemoteControlIncomingData(data)
        @unknown default:
            break
        }
    }

    private func handleRemoteControlIncomingData(_ data: Data) async {
        let relayConnectionID = remoteRelayConnectionID(from: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let relaySignal = try? decoder.decode(RemoteRelayControlSignal.self, from: data) {
            await handleRemoteRelaySignal(relaySignal)
            return
        }

        guard let envelope = try? decoder.decode(RemoteControlEnvelope.self, from: data) else {
            return
        }
        guard envelope.schemaVersion == RemoteControlProtocol.schemaVersion else {
            return
        }
        guard envelope.sessionID == remoteControlStatus.session?.sessionID else {
            return
        }

        let ingestResult = ingestRemoteInboundSequence(envelope.seq, relayConnectionID: relayConnectionID)
        switch ingestResult {
        case .accepted:
            break
        case .stale:
            return
        case .gapDetected:
            await sendRemoteControlSnapshot(reason: .sequenceGap, force: true)
            return
        }

        switch envelope.payload {
        case let .command(commandPayload):
            applyRemoteControlCommand(commandPayload)
            await sendRemoteControlSnapshot(reason: .commandApplied, force: true)
        case .event, .snapshot, .hello, .authOK:
            break
        }
    }

    private func handleRemoteRelaySignal(_ signal: RemoteRelayControlSignal) async {
        switch signal.type {
        case "auth_ok":
            remoteControlReconnectAttempt = 0
            remoteControlRelayAuthenticated = true
            if let connectedDeviceCount = signal.connectedDeviceCount {
                await remoteControlBroker.updateConnectedDeviceCount(connectedDeviceCount)
            }
            await refreshRemoteControlStatus()
            remoteControlStatusMessage = "Remote relay authenticated."
            await sendRemoteControlHello()
            await sendRemoteControlSnapshot(reason: .websocketAuthenticated, force: true)
            primeRemoteControlEventBaselines()
        case "relay.device_count":
            if let connectedDeviceCount = signal.connectedDeviceCount {
                await remoteControlBroker.updateConnectedDeviceCount(connectedDeviceCount)
                await refreshRemoteControlStatus()
            }
        case "relay.snapshot_request":
            await sendRemoteControlSnapshot(reason: .snapshotRequest, force: true)
        case "relay.pair_request":
            handleRemotePairRequestSignal(signal)
        case "relay.pair_result":
            handleRemotePairResultSignal(signal)
        default:
            break
        }
    }

    func approveRemoteControlPairRequest() {
        sendRemotePairDecision(approved: true)
    }

    func denyRemoteControlPairRequest() {
        sendRemotePairDecision(approved: false)
    }

    private func startRemoteControlSnapshotPump() {
        remoteControlSnapshotPumpTask?.cancel()
        remoteControlSnapshotPumpTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.remoteControlSnapshotPumpNanoseconds)
                guard !Task.isCancelled else { return }
                await sendRemoteControlDeltaEventsIfNeeded()
                await sendRemoteControlSnapshot(reason: .stateChanged, force: false)
            }
        }
    }

    private func sendRemoteControlSnapshot(reason: RemoteControlSnapshotReason, force: Bool) async {
        guard remoteControlRelayAuthenticated,
              let session = remoteControlStatus.session
        else {
            return
        }

        let snapshotSignature = remoteControlSnapshotSignature()
        if !force, snapshotSignature == remoteControlLastSnapshotSignature {
            return
        }

        let snapshotPayload = buildRemoteControlSnapshotPayload()
        let envelope = RemoteControlEnvelope(
            sessionID: session.sessionID,
            seq: nextRemoteControlOutboundSequence(),
            payload: .snapshot(snapshotPayload)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            try await sendRemoteControlEnvelope(envelope, encoder: encoder)
            remoteControlLastSnapshotSignature = snapshotSignature
            await remoteControlBroker.bumpActivity()
            if force {
                remoteControlStatusMessage = "Remote sync updated (\(reason.rawValue))."
            }
        } catch {
            remoteControlStatusMessage = "Failed to send remote snapshot: \(error.localizedDescription)"
        }
    }

    private func sendRemoteControlHello() async {
        guard remoteControlRelayAuthenticated,
              let session = remoteControlStatus.session
        else {
            return
        }
        let helloPayload = RemoteControlHelloPayload(
            role: .desktop,
            clientName: "CodexChat Desktop",
            supportsApprovals: allowRemoteApprovals
        )
        let envelope = RemoteControlEnvelope(
            sessionID: session.sessionID,
            seq: nextRemoteControlOutboundSequence(),
            payload: .hello(helloPayload)
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try await sendRemoteControlEnvelope(envelope, encoder: encoder)
        } catch {
            appendLog(.warning, "Failed to send remote hello payload: \(error.localizedDescription)")
        }
    }

    private func sendRemoteControlEnvelope(_ envelope: RemoteControlEnvelope, encoder: JSONEncoder) async throws {
        guard let websocketTask = remoteControlWebSocketTask else {
            throw URLError(.networkConnectionLost)
        }
        let payloadData = try encoder.encode(envelope)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        try await websocketTask.send(.string(payloadString))
    }

    private func sendRemoteControlSignal(_ payload: [String: Any]) async throws {
        guard let websocketTask = remoteControlWebSocketTask else {
            throw URLError(.networkConnectionLost)
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let raw = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        try await websocketTask.send(.string(raw))
    }

    private func sendRemoteControlAuthSignalIfNeeded() async {
        guard let authToken = remoteControlWebSocketAuthToken else {
            return
        }

        do {
            try await sendRemoteControlSignal(
                [
                    "type": "relay.auth",
                    "token": authToken,
                ]
            )
        } catch {
            appendLog(.warning, "Failed to authenticate remote relay websocket: \(error.localizedDescription)")
        }
    }

    private func sendRemoteControlDeltaEventsIfNeeded() async {
        guard remoteControlRelayAuthenticated,
              remoteControlStatus.session != nil
        else {
            return
        }

        await sendRemoteControlMessageEventsIfNeeded()
        await sendRemoteControlTurnStateEventIfNeeded()
        await sendRemoteControlApprovalEventsIfNeeded()
    }

    private func sendRemoteControlMessageEventsIfNeeded() async {
        guard let selectedThreadID else {
            remoteControlLastEventEntryIDsByThreadID = [:]
            return
        }

        let entries = Array(transcriptStore[selectedThreadID, default: []].suffix(Self.remoteControlSnapshotMessageLimit))
        let previousIDs = remoteControlLastEventEntryIDsByThreadID[selectedThreadID, default: []]
        var nextIDs = Set<UUID>()

        for entry in entries {
            nextIDs.insert(entry.id)
            guard !previousIDs.contains(entry.id),
                  let eventPayload = remoteControlEventPayload(for: entry)
            else {
                continue
            }
            await sendRemoteControlEvent(eventPayload)
        }

        remoteControlLastEventEntryIDsByThreadID = [selectedThreadID: nextIDs]
    }

    private func sendRemoteControlTurnStateEventIfNeeded() async {
        guard let selectedThreadID else {
            remoteControlLastTurnStateByThreadID = [:]
            return
        }

        let isRunning = activeTurnThreadIDs.contains(selectedThreadID)
        let previousValue = remoteControlLastTurnStateByThreadID[selectedThreadID]
        guard previousValue != isRunning else {
            return
        }

        await sendRemoteControlEvent(
            RemoteControlEventPayload(
                name: "turn.status.update",
                threadID: selectedThreadID.uuidString,
                body: isRunning ? "running" : "idle"
            )
        )
        remoteControlLastTurnStateByThreadID = [selectedThreadID: isRunning]
    }

    private func sendRemoteControlApprovalEventsIfNeeded() async {
        let snapshots = buildRemoteApprovalSnapshots()
        var currentByID: [Int: RemoteControlApprovalSnapshot] = [:]
        for snapshot in snapshots {
            guard let requestID = Int(snapshot.requestID) else {
                continue
            }
            currentByID[requestID] = snapshot
        }

        let currentIDs = Set(currentByID.keys)
        let previousIDs = remoteControlLastPendingApprovalRequestIDs

        for requestID in currentIDs.subtracting(previousIDs).sorted() {
            guard let snapshot = currentByID[requestID] else {
                continue
            }
            await sendRemoteControlEvent(
                RemoteControlEventPayload(
                    name: "approval.requested",
                    threadID: snapshot.threadID,
                    body: snapshot.summary
                )
            )
        }

        for requestID in previousIDs.subtracting(currentIDs).sorted() {
            await sendRemoteControlEvent(
                RemoteControlEventPayload(
                    name: "approval.resolved",
                    threadID: nil,
                    body: "Approval #\(requestID) resolved."
                )
            )
        }

        remoteControlLastPendingApprovalRequestIDs = currentIDs
    }

    private func remoteControlEventPayload(for entry: TranscriptEntry) -> RemoteControlEventPayload? {
        switch entry {
        case let .message(message):
            RemoteControlEventPayload(
                name: "thread.message.append",
                threadID: message.threadId.uuidString,
                body: message.text,
                messageID: message.id.uuidString,
                role: message.role.rawValue,
                createdAt: message.createdAt
            )
        case let .actionCard(card):
            RemoteControlEventPayload(
                name: "thread.message.append",
                threadID: card.threadID.uuidString,
                body: "\(card.title): \(card.detail)",
                messageID: card.id.uuidString,
                role: ChatMessageRole.system.rawValue,
                createdAt: card.createdAt
            )
        }
    }

    private func sendRemoteControlEvent(_ payload: RemoteControlEventPayload) async {
        guard let session = remoteControlStatus.session else {
            return
        }

        let envelope = RemoteControlEnvelope(
            sessionID: session.sessionID,
            seq: nextRemoteControlOutboundSequence(),
            payload: .event(payload)
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try await sendRemoteControlEnvelope(envelope, encoder: encoder)
            await remoteControlBroker.bumpActivity()
        } catch {
            appendLog(.warning, "Failed to send remote event payload: \(error.localizedDescription)")
        }
    }

    private func primeRemoteControlEventBaselines() {
        remoteControlLastEventEntryIDsByThreadID = [:]
        remoteControlLastTurnStateByThreadID = [:]
        remoteControlLastPendingApprovalRequestIDs = []

        if let selectedThreadID {
            let entries = Array(transcriptStore[selectedThreadID, default: []].suffix(Self.remoteControlSnapshotMessageLimit))
            remoteControlLastEventEntryIDsByThreadID[selectedThreadID] = Set(entries.map(\.id))
            remoteControlLastTurnStateByThreadID[selectedThreadID] = activeTurnThreadIDs.contains(selectedThreadID)
        }

        let requestIDs = buildRemoteApprovalSnapshots().compactMap { Int($0.requestID) }
        remoteControlLastPendingApprovalRequestIDs = Set(requestIDs)
    }

    private func nextRemoteControlOutboundSequence() -> UInt64 {
        remoteControlOutboundSequence &+= 1
        return remoteControlOutboundSequence
    }

    private func remoteRelayConnectionID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any],
              let relayConnectionID = object["relayConnectionID"] as? String
        else {
            return nil
        }

        let trimmed = relayConnectionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func ingestRemoteInboundSequence(
        _ sequence: UInt64,
        relayConnectionID: String?
    ) -> RemoteControlSequenceIngestResult {
        guard let relayConnectionID else {
            return remoteControlInboundSequenceTracker.ingest(sequence)
        }

        var tracker = remoteControlInboundSequenceTrackersByConnectionID[relayConnectionID] ?? RemoteControlSequenceTracker()
        let result = tracker.ingest(sequence)
        remoteControlInboundSequenceTrackersByConnectionID[relayConnectionID] = tracker
        return result
    }

    private func remoteControlSnapshotSignature() -> String {
        let projectUpdatedStamp = projects.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let threadUpdatedStamp = (threads + generalThreads)
            .map(\.updatedAt.timeIntervalSince1970)
            .max() ?? 0
        let selectedThreadRevision = selectedThreadID.flatMap { transcriptRevisionsByThreadID[$0] } ?? 0

        return [
            "p:\(projects.count)",
            "pAt:\(projectUpdatedStamp)",
            "t:\(threads.count + generalThreads.count)",
            "tAt:\(threadUpdatedStamp)",
            "sp:\(selectedProjectID?.uuidString ?? "nil")",
            "st:\(selectedThreadID?.uuidString ?? "nil")",
            "tr:\(selectedThreadRevision)",
            "turn:\(isTurnInProgress)",
            "approval:\(totalPendingApprovalCount)",
            "active:\(activeTurnThreadIDs.count)",
        ].joined(separator: "|")
    }

    private func buildRemoteControlSnapshotPayload() -> RemoteControlSnapshotPayload {
        let projectSnapshots = projects.map { project in
            RemoteControlProjectSnapshot(
                id: project.id.uuidString,
                name: project.name
            )
        }

        let activeThreads = threads + generalThreads
        let threadSnapshots = activeThreads.map { thread in
            RemoteControlThreadSnapshot(
                id: thread.id.uuidString,
                projectID: thread.projectId.uuidString,
                title: thread.title,
                isPinned: thread.isPinned
            )
        }

        let selectedEntries: [TranscriptEntry] = {
            guard let selectedThreadID else { return [] }
            return Array(transcriptStore[selectedThreadID, default: []].suffix(Self.remoteControlSnapshotMessageLimit))
        }()

        let messageSnapshots = selectedEntries.compactMap { entry -> RemoteControlMessageSnapshot? in
            switch entry {
            case let .message(message):
                return RemoteControlMessageSnapshot(
                    id: message.id.uuidString,
                    threadID: message.threadId.uuidString,
                    role: message.role.rawValue,
                    text: message.text,
                    createdAt: message.createdAt
                )
            case let .actionCard(action):
                return RemoteControlMessageSnapshot(
                    id: action.id.uuidString,
                    threadID: action.threadID.uuidString,
                    role: ChatMessageRole.system.rawValue,
                    text: "\(action.title): \(action.detail)",
                    createdAt: action.createdAt
                )
            }
        }

        let turnState: RemoteControlTurnStateSnapshot? = {
            guard let selectedThreadID else { return nil }
            return RemoteControlTurnStateSnapshot(
                threadID: selectedThreadID.uuidString,
                isTurnInProgress: activeTurnThreadIDs.contains(selectedThreadID),
                isAwaitingApproval: hasPendingApproval(for: selectedThreadID)
            )
        }()

        let approvalSnapshots = buildRemoteApprovalSnapshots()

        return RemoteControlSnapshotPayload(
            projects: projectSnapshots,
            threads: threadSnapshots,
            selectedProjectID: selectedProjectID?.uuidString,
            selectedThreadID: selectedThreadID?.uuidString,
            messages: messageSnapshots,
            turnState: turnState,
            pendingApprovals: approvalSnapshots
        )
    }

    private func applyRemoteControlCommand(_ command: RemoteControlCommandPayload) {
        switch command.name {
        case .projectSelect:
            applyRemoteProjectSelectCommand(command)
        case .threadSelect:
            applyRemoteThreadSelectCommand(command)
        case .threadSendMessage:
            applyRemoteThreadSendCommand(command)
        case .approvalRespond:
            applyRemoteApprovalCommand(command)
        }
    }

    private func applyRemoteProjectSelectCommand(_ command: RemoteControlCommandPayload) {
        guard let projectIDString = command.projectID,
              let projectID = UUID(uuidString: projectIDString),
              projects.contains(where: { $0.id == projectID })
        else {
            return
        }

        selectProject(projectID)
    }

    private func applyRemoteThreadSelectCommand(_ command: RemoteControlCommandPayload) {
        guard let threadIDString = command.threadID,
              let threadID = UUID(uuidString: threadIDString)
        else {
            return
        }

        let isKnownThread = (threads + generalThreads + archivedThreads).contains(where: { $0.id == threadID })
        guard isKnownThread else {
            return
        }

        selectThread(threadID)
    }

    private func applyRemoteThreadSendCommand(_ command: RemoteControlCommandPayload) {
        let text = command.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return
        }

        if let projectIDString = command.projectID,
           let projectID = UUID(uuidString: projectIDString),
           selectedProjectID != projectID,
           projects.contains(where: { $0.id == projectID })
        {
            selectProject(projectID)
        }

        if let threadIDString = command.threadID,
           let threadID = UUID(uuidString: threadIDString),
           selectedThreadID != threadID,
           (threads + generalThreads + archivedThreads).contains(where: { $0.id == threadID })
        {
            selectThread(threadID)
        }

        if selectedThreadID == nil, !hasActiveDraftChatForSelectedProject {
            startChatFromEmptyState()
        }

        composerText = text
        sendMessage()
    }

    private func applyRemoteApprovalCommand(_ command: RemoteControlCommandPayload) {
        guard allowRemoteApprovals else {
            return
        }

        guard let decisionRaw = command.approvalDecision?.lowercased(),
              let decision = remoteApprovalDecision(from: decisionRaw)
        else {
            return
        }

        let requestID = command.approvalRequestID.flatMap(Int.init)
        submitRemoteApprovalDecision(decision, requestID: requestID)
    }

    private func handleRemotePairRequestSignal(_ signal: RemoteRelayControlSignal) {
        guard let requestID = signal.requestID,
              !requestID.isEmpty
        else {
            return
        }

        remoteControlPendingPairRequest = RemoteControlPairRequestPrompt(
            requestID: requestID,
            requesterIP: signal.requesterIP,
            requestedAt: signal.requestedAt,
            expiresAt: signal.expiresAt
        )
        remoteControlStatusMessage = "Remote device requested pairing approval."
        isRemoteControlSheetVisible = true
    }

    private func handleRemotePairResultSignal(_ signal: RemoteRelayControlSignal) {
        guard let requestID = signal.requestID else {
            return
        }

        if remoteControlPendingPairRequest?.requestID == requestID {
            remoteControlPendingPairRequest = nil
        }

        if let approved = signal.approved {
            remoteControlStatusMessage = approved
                ? "Approved remote pairing request."
                : "Denied remote pairing request."
        }
    }

    private func sendRemotePairDecision(approved: Bool) {
        guard let pendingRequest = remoteControlPendingPairRequest else {
            return
        }
        guard let session = remoteControlStatus.session else {
            remoteControlStatusMessage = "Remote session is no longer active."
            remoteControlPendingPairRequest = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                try await sendRemoteControlSignal(
                    [
                        "type": "relay.pair_decision",
                        "sessionID": session.sessionID,
                        "requestID": pendingRequest.requestID,
                        "approved": approved,
                    ]
                )
                remoteControlPendingPairRequest = nil
                remoteControlStatusMessage = approved
                    ? "Approved remote pairing request."
                    : "Denied remote pairing request."
            } catch {
                remoteControlStatusMessage = "Failed to send pairing decision: \(error.localizedDescription)"
            }
        }
    }

    private func remoteApprovalDecision(from rawDecision: String) -> RuntimeApprovalDecision? {
        switch rawDecision {
        case "approve", "approve_once", "approve-once":
            .approveOnce
        case "approve_for_session", "approve-session", "approveforsession":
            .approveForSession
        case "decline", "reject":
            .decline
        default:
            nil
        }
    }

    private func buildRemoteApprovalSnapshots() -> [RemoteControlApprovalSnapshot] {
        var snapshots: [RemoteControlApprovalSnapshot] = []
        var seenRequestIDs = Set<Int>()

        for (threadID, requests) in approvalStateMachine.pendingByThreadID.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            for request in requests.sorted(by: { $0.id < $1.id }) {
                guard seenRequestIDs.insert(request.id).inserted else {
                    continue
                }
                snapshots.append(
                    RemoteControlApprovalSnapshot(
                        requestID: String(request.id),
                        threadID: threadID.uuidString,
                        summary: remoteApprovalSummary(for: request)
                    )
                )
            }
        }

        for request in unscopedApprovalRequests.sorted(by: { $0.id < $1.id }) {
            guard seenRequestIDs.insert(request.id).inserted else {
                continue
            }
            snapshots.append(
                RemoteControlApprovalSnapshot(
                    requestID: String(request.id),
                    threadID: nil,
                    summary: remoteApprovalSummary(for: request)
                )
            )
        }

        if let activeApprovalRequest,
           seenRequestIDs.insert(activeApprovalRequest.id).inserted
        {
            let threadID = approvalStateMachine.threadID(for: activeApprovalRequest.id)?.uuidString
            snapshots.append(
                RemoteControlApprovalSnapshot(
                    requestID: String(activeApprovalRequest.id),
                    threadID: threadID,
                    summary: remoteApprovalSummary(for: activeApprovalRequest)
                )
            )
        }

        return snapshots
    }

    private func remoteApprovalSummary(for request: RuntimeApprovalRequest) -> String {
        if let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty
        {
            return reason
        }
        if !request.command.isEmpty {
            return request.command.joined(separator: " ")
        }
        let detail = request.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            return detail
        }
        return request.method
    }

    private static func remoteTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
