import CodexChatCore
import CodexChatRemoteControl
import CodexKit
import Foundation

private struct RemoteControlCommandAckReplayCache {
    private var ackByCommandIdentity: [String: RemoteControlCommandAckPayload] = [:]
    private var commandIdentityOrder: [String] = []

    func ack(for commandIdentity: String) -> RemoteControlCommandAckPayload? {
        ackByCommandIdentity[commandIdentity]
    }

    mutating func store(
        _ ack: RemoteControlCommandAckPayload,
        for commandIdentity: String,
        limit: Int
    ) {
        if ackByCommandIdentity[commandIdentity] == nil {
            commandIdentityOrder.append(commandIdentity)
        }
        ackByCommandIdentity[commandIdentity] = ack

        let overflow = commandIdentityOrder.count - limit
        if overflow > 0 {
            let evictedCommandIdentities = commandIdentityOrder.prefix(overflow)
            for commandIdentity in evictedCommandIdentities {
                ackByCommandIdentity.removeValue(forKey: commandIdentity)
            }
            commandIdentityOrder.removeFirst(overflow)
        }
    }
}

@MainActor
private enum RemoteControlCommandAckReplayStore {
    private static var cacheByModelID: [ObjectIdentifier: RemoteControlCommandAckReplayCache] = [:]

    static func ack(for model: AppModel, commandIdentity: String) -> RemoteControlCommandAckPayload? {
        cacheByModelID[ObjectIdentifier(model)]?.ack(for: commandIdentity)
    }

    static func store(
        _ ack: RemoteControlCommandAckPayload,
        for model: AppModel,
        commandIdentity: String,
        limit: Int
    ) {
        let modelID = ObjectIdentifier(model)
        var cache = cacheByModelID[modelID] ?? RemoteControlCommandAckReplayCache()
        cache.store(ack, for: commandIdentity, limit: limit)
        cacheByModelID[modelID] = cache
    }

    static func reset(for model: AppModel) {
        cacheByModelID.removeValue(forKey: ObjectIdentifier(model))
    }
}

extension AppModel {
    private func applyRemoteControlCommand(
        _ command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) async -> RemoteControlCommandAckPayload {
        switch command.name {
        case .projectSelect:
            applyRemoteProjectSelectCommand(command, inboundCommandSequence: inboundCommandSequence)
        case .threadSelect:
            applyRemoteThreadSelectCommand(command, inboundCommandSequence: inboundCommandSequence)
        case .threadSendMessage:
            await applyRemoteThreadSendCommand(command, inboundCommandSequence: inboundCommandSequence)
        case .runtimeRequestRespond:
            await applyRemoteRuntimeRequestCommand(command, inboundCommandSequence: inboundCommandSequence)
        }
    }

    func processRemoteControlCommand(
        _ command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) async -> RemoteControlCommandAckPayload {
        guard normalizedRemoteControlCommandID(for: command) != nil else {
            let ack = remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "command_id_required"
            )
            await sendRemoteControlCommandAck(ack)
            return ack
        }

        if let cachedAck = cachedRemoteControlCommandAck(for: command) {
            await sendRemoteControlCommandAck(cachedAck)
            return cachedAck
        }

        let ack = await applyRemoteControlCommand(
            command,
            inboundCommandSequence: inboundCommandSequence
        )
        cacheRemoteControlCommandAck(ack, for: command)
        await sendRemoteControlCommandAck(ack)
        if ack.status == .accepted {
            await queueRemoteControlSyncFlush(
                reason: .commandApplied,
                forceSnapshot: true
            )
        }
        return ack
    }

    private func sendRemoteControlCommandAck(_ payload: RemoteControlCommandAckPayload) async {
        guard let session = remoteControlStatus.session else {
            return
        }

        let envelope = RemoteControlEnvelope(
            sessionID: session.sessionID,
            seq: nextRemoteControlOutboundSequence(),
            payload: .commandAck(payload)
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try await sendRemoteControlEnvelope(envelope, encoder: encoder)
            await remoteControlBroker.bumpActivity()
        } catch {
            appendLog(.warning, "Failed to send remote command ack payload: \(error.localizedDescription)")
        }
    }

    func replayRemoteControlCommandAckIfCached(
        for command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) async {
        guard normalizedRemoteControlCommandID(for: command) != nil else {
            await sendRemoteControlCommandAck(
                remoteControlCommandAck(
                    command: command,
                    commandSequence: inboundCommandSequence,
                    status: .rejected,
                    reason: "command_id_required"
                )
            )
            return
        }
        guard let cachedAck = cachedRemoteControlCommandAck(for: command) else {
            return
        }
        await sendRemoteControlCommandAck(cachedAck)
    }

    private func cachedRemoteControlCommandAck(
        for command: RemoteControlCommandPayload
    ) -> RemoteControlCommandAckPayload? {
        guard let commandIdentity = remoteControlCommandIdentity(for: command) else {
            return nil
        }
        return RemoteControlCommandAckReplayStore.ack(
            for: self,
            commandIdentity: commandIdentity
        )
    }

    private func cacheRemoteControlCommandAck(
        _ ack: RemoteControlCommandAckPayload,
        for command: RemoteControlCommandPayload
    ) {
        guard let commandIdentity = remoteControlCommandIdentity(for: command) else {
            return
        }
        RemoteControlCommandAckReplayStore.store(
            ack,
            for: self,
            commandIdentity: commandIdentity,
            limit: Self.remoteControlCommandAckReplayCacheLimit
        )
    }

    func resetRemoteControlCommandAckReplayCache() {
        RemoteControlCommandAckReplayStore.reset(for: self)
    }

    private func normalizedRemoteControlCommandID(for command: RemoteControlCommandPayload) -> String? {
        let trimmed = command.commandID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func remoteControlCommandIdentity(for command: RemoteControlCommandPayload) -> String? {
        guard let commandID = normalizedRemoteControlCommandID(for: command) else {
            return nil
        }

        let canonicalCommand = RemoteControlCommandPayload(
            name: command.name,
            commandID: commandID,
            threadID: command.threadID,
            projectID: command.projectID,
            text: command.text,
            runtimeRequestID: command.runtimeRequestID,
            runtimeRequestKind: command.runtimeRequestKind,
            runtimeRequestResponse: command.runtimeRequestResponse
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let encoded = try? encoder.encode(canonicalCommand),
              let identity = String(data: encoded, encoding: .utf8)
        else {
            return nil
        }

        return identity
    }

    private func remoteControlTranscriptMutationStamp(for threadID: UUID?) -> UInt64 {
        if let threadID {
            return transcriptRevisionsByThreadID[threadID] ?? 0
        }
        return transcriptRevisionsByThreadID.values.reduce(0, &+)
    }

    private func waitForRemoteControlTranscriptMutation(
        threadID: UUID?,
        baselineMutationStamp: UInt64
    ) async -> Bool {
        let timeoutSeconds = Double(Self.remoteControlCommandMutationTimeoutNanoseconds) / 1_000_000_000
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let currentMutationStamp = remoteControlTranscriptMutationStamp(for: threadID)
            if currentMutationStamp > baselineMutationStamp {
                return true
            }
            try? await Task.sleep(nanoseconds: Self.remoteControlCommandMutationPollNanoseconds)
            if Task.isCancelled {
                return false
            }
        }

        return remoteControlTranscriptMutationStamp(for: threadID) > baselineMutationStamp
    }

    private func applyRemoteProjectSelectCommand(
        _ command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) -> RemoteControlCommandAckPayload {
        guard let projectIDString = command.projectID,
              let projectID = UUID(uuidString: projectIDString)
        else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "invalid_project"
            )
        }

        guard projects.contains(where: { $0.id == projectID }) else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "unknown_project"
            )
        }

        selectProject(projectID)
        return remoteControlCommandAck(
            command: command,
            commandSequence: inboundCommandSequence,
            status: .accepted
        )
    }

    private func applyRemoteThreadSelectCommand(
        _ command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) -> RemoteControlCommandAckPayload {
        guard let threadIDString = command.threadID,
              let threadID = UUID(uuidString: threadIDString)
        else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "invalid_thread"
            )
        }

        let isKnownThread = (threads + generalThreads + archivedThreads).contains(where: { $0.id == threadID })
        guard isKnownThread else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "unknown_thread"
            )
        }

        selectThread(threadID)
        return remoteControlCommandAck(
            command: command,
            commandSequence: inboundCommandSequence,
            status: .accepted,
            threadID: threadID.uuidString
        )
    }

    private func applyRemoteThreadSendCommand(
        _ command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) async -> RemoteControlCommandAckPayload {
        let text = command.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "empty_message"
            )
        }

        if runtimePool == nil || runtimeStatus != .connected {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "desktop_offline"
            )
        }

        if let projectIDString = command.projectID {
            guard let projectID = UUID(uuidString: projectIDString) else {
                return remoteControlCommandAck(
                    command: command,
                    commandSequence: inboundCommandSequence,
                    status: .rejected,
                    reason: "invalid_project"
                )
            }
            guard projects.contains(where: { $0.id == projectID }) else {
                return remoteControlCommandAck(
                    command: command,
                    commandSequence: inboundCommandSequence,
                    status: .rejected,
                    reason: "unknown_project"
                )
            }

            if selectedProjectID != projectID {
                selectProject(projectID)
            }
        }

        if let threadIDString = command.threadID {
            guard let threadID = UUID(uuidString: threadIDString) else {
                return remoteControlCommandAck(
                    command: command,
                    commandSequence: inboundCommandSequence,
                    status: .rejected,
                    reason: "invalid_thread"
                )
            }

            let isKnownThread = (threads + generalThreads + archivedThreads).contains(where: { $0.id == threadID })
            guard isKnownThread else {
                return remoteControlCommandAck(
                    command: command,
                    commandSequence: inboundCommandSequence,
                    status: .rejected,
                    reason: "unknown_thread"
                )
            }

            if selectedThreadID != threadID {
                selectThread(threadID)
            }
        }

        if selectedThreadID == nil, !hasActiveDraftChatForSelectedProject {
            activateDraftChatFromCurrentContext()
        }

        guard selectedThreadID != nil else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "thread_required"
            )
        }

        if hasPendingApprovalForSelectedThread || isSelectedThreadApprovalInProgress {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "runtime_request_required",
                threadID: selectedThreadID?.uuidString
            )
        }

        let observedThreadID = selectedThreadID
        guard canDispatchSelectedThreadImmediatelyForRemoteSend else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "desktop_busy",
                threadID: observedThreadID?.uuidString
            )
        }
        guard let observedThreadID,
              let observedProjectID = selectedProjectID
        else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "thread_required"
            )
        }

        let baselineMutationStamp = remoteControlTranscriptMutationStamp(for: observedThreadID)
        submitRemoteThreadMessage(
            text: text,
            threadID: observedThreadID,
            projectID: observedProjectID
        )

        let didObserveMutation = await waitForRemoteControlTranscriptMutation(
            threadID: observedThreadID,
            baselineMutationStamp: baselineMutationStamp
        )
        guard didObserveMutation else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "desktop_busy",
                threadID: observedThreadID.uuidString
            )
        }

        return remoteControlCommandAck(
            command: command,
            commandSequence: inboundCommandSequence,
            status: .accepted,
            threadID: observedThreadID.uuidString
        )
    }

    private func submitRemoteThreadMessage(text: String, threadID: UUID, projectID: UUID) {
        markTurnStartPending(threadID: threadID)

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                guard let project = try await projectRepository?.getProject(id: projectID) else {
                    throw CodexChatCoreError.missingRecord(projectID.uuidString)
                }

                try await dispatchNow(
                    text: text,
                    threadID: threadID,
                    projectID: project.id,
                    projectPath: project.path,
                    sourceQueueItemID: nil,
                    priority: .selected
                )
            } catch {
                clearTurnStartPending(threadID: threadID)
                appendLog(.error, "Remote thread send failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyRemoteRuntimeRequestCommand(
        _ command: RemoteControlCommandPayload,
        inboundCommandSequence: UInt64
    ) async -> RemoteControlCommandAckPayload {
        guard allowRemoteApprovals else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "remote_runtime_requests_disabled"
            )
        }

        guard let requestIDRaw = command.runtimeRequestID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestIDRaw.isEmpty
        else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "runtime_request_required"
            )
        }
        guard let requestID = Int(requestIDRaw) else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "invalid_runtime_request"
            )
        }
        guard let pendingRequest = remoteControllableRuntimeRequest(id: requestID) else {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "unknown_runtime_request"
            )
        }

        if let claimedKind = command.runtimeRequestKind,
           claimedKind != remoteControlRuntimeRequestKind(for: pendingRequest.kind)
        {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "invalid_runtime_request"
            )
        }

        do {
            try await respondToRemoteRuntimeRequest(pendingRequest, command: command)
            let summary = remoteControlRuntimeRequestSummary(for: pendingRequest)
            await sendRemoteControlEvent(
                RemoteControlEventPayload(
                    name: "runtime_request.responded",
                    threadID: summary.threadID,
                    body: "\(summary.title): \(summary.summary)"
                )
            )
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .accepted
            )
        } catch let error as ServerRequestSubmissionError {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: remoteRuntimeRequestReason(for: error)
            )
        } catch let error as ApprovalDecisionSubmissionError {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: remoteRuntimeRequestReason(for: error)
            )
        } catch RemoteRuntimeRequestCommandError.invalidPayload {
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "invalid_runtime_request"
            )
        } catch let error as CodexRuntimeError {
            let reason = switch error {
            case .processNotRunning, .transportClosed:
                "desktop_offline"
            case let .invalidResponse(detail)
                where detail.contains("Unknown pooled approval request id")
                || detail.contains("Unknown approval request id")
                || detail.contains("Unknown pooled server request id")
                || detail.contains("Unknown server request id"):
                "unknown_runtime_request"
            default:
                "runtime_request_failed"
            }
            let summary = remoteControlRuntimeRequestSummary(for: pendingRequest)
            recordRuntimeRequestSupportEvent(phase: .failed, summary: summary)
            appendLog(.warning, "Remote runtime request command failed for request \(requestID): \(error.localizedDescription)")
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: reason
            )
        } catch {
            let summary = remoteControlRuntimeRequestSummary(for: pendingRequest)
            recordRuntimeRequestSupportEvent(phase: .failed, summary: summary)
            appendLog(.warning, "Remote runtime request command failed for request \(requestID): \(error.localizedDescription)")
            return remoteControlCommandAck(
                command: command,
                commandSequence: inboundCommandSequence,
                status: .rejected,
                reason: "runtime_request_failed"
            )
        }
    }

    private func remoteControlCommandAck(
        command: RemoteControlCommandPayload,
        commandSequence: UInt64,
        status: RemoteControlCommandAckStatus,
        reason: String? = nil,
        threadID: String? = nil
    ) -> RemoteControlCommandAckPayload {
        RemoteControlCommandAckPayload(
            commandSeq: commandSequence,
            commandID: command.commandID,
            commandName: command.name,
            status: status,
            reason: reason,
            threadID: threadID ?? command.threadID
        )
    }

    private func remoteApprovalDecision(from rawDecision: String) -> RuntimeApprovalDecision? {
        switch rawDecision {
        case "approve", "approve_once", "approve-once":
            .approveOnce
        case "approve_for_session", "approve-session", "approveforsession":
            .approveForSession
        case "decline", "reject":
            .decline
        case "cancel":
            .cancel
        default:
            nil
        }
    }

    private func remoteControllableRuntimeRequest(id requestID: Int) -> RuntimeServerRequest? {
        if let approval = resolvePendingApprovalRequest(id: requestID) {
            return .approval(approval)
        }
        return resolvePendingServerRequest(id: requestID)
    }

    private func remoteControlRuntimeRequestKind(
        for kind: RuntimeServerRequestKind
    ) -> RemoteControlRuntimeRequestKind {
        switch kind {
        case .approval:
            .approval
        case .permissionsApproval:
            .permissionsApproval
        case .userInput:
            .userInput
        case .mcpElicitation:
            .mcpElicitation
        case .dynamicToolCall:
            .dynamicToolCall
        }
    }

    private func respondToRemoteRuntimeRequest(
        _ request: RuntimeServerRequest,
        command: RemoteControlCommandPayload
    ) async throws {
        switch request {
        case let .approval(approval):
            guard let decisionRaw = command.runtimeRequestResponse?.decision?.lowercased(),
                  let decision = remoteApprovalDecision(from: decisionRaw)
            else {
                throw RemoteRuntimeRequestCommandError.invalidPayload
            }
            try await submitRemoteApprovalDecision(decision, requestID: approval.id)
        case let .permissions(permission):
            let response = try RemoteRuntimeRequestResponseInterpreter.permissionsResponse(
                for: permission,
                payload: command.runtimeRequestResponse
            )
            try await submitRemotePermissionsRequestResponse(
                requestID: permission.id,
                permissions: response.permissions,
                scope: response.scope
            )
        case let .userInput(userInput):
            let response = RemoteRuntimeRequestResponseInterpreter.userInputResponse(
                for: userInput,
                payload: command.runtimeRequestResponse
            )
            try await submitRemoteUserInputRequestResponse(
                requestID: userInput.id,
                text: response.text,
                optionID: response.optionID
            )
        case let .mcpElicitation(mcp):
            try await submitRemoteMCPElicitationResponse(
                requestID: mcp.id,
                text: RemoteRuntimeRequestResponseInterpreter.mcpElicitationText(
                    payload: command.runtimeRequestResponse
                )
            )
        case let .dynamicToolCall(tool):
            let approved = try RemoteRuntimeRequestResponseInterpreter.dynamicToolCallApproval(
                payload: command.runtimeRequestResponse
            )
            try await submitRemoteDynamicToolCallResponse(requestID: tool.id, approved: approved)
        }
    }

    private func remoteControlRuntimeRequestSummary(
        for request: RuntimeServerRequest
    ) -> RuntimeRequestSupportSummary {
        switch request {
        case let .approval(approval):
            let localThreadID = approvalStateMachine.threadID(for: approval.id)
            return runtimeRequestSupportSummary(for: approval, localThreadID: localThreadID)
        default:
            let localThreadID = serverRequestStateMachine.threadID(for: request.id)
            return runtimeRequestSupportSummary(for: request, localThreadID: localThreadID)
        }
    }

    private func remoteRuntimeRequestReason(
        for error: ApprovalDecisionSubmissionError
    ) -> String {
        switch error {
        case .runtimeUnavailable:
            "desktop_offline"
        case .requestNotFound:
            "unknown_runtime_request"
        }
    }

    private func remoteRuntimeRequestReason(
        for error: ServerRequestSubmissionError
    ) -> String {
        switch error {
        case .runtimeUnavailable:
            "desktop_offline"
        case .requestNotFound:
            "unknown_runtime_request"
        }
    }
}

enum RemoteRuntimeRequestCommandError: Error {
    case invalidPayload
}
