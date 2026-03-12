import CodexChatCore
import CodexChatInfra
import CodexChatRemoteControl
@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

private actor RemoteEnvelopeRecorder {
    private(set) var entries: [RemoteControlEnvelope] = []
    private(set) var timestamps: [Date] = []
    private(set) var snapshotSawExpectedMessage = false

    func record(_ envelope: RemoteControlEnvelope, snapshotSawExpectedMessage: Bool = false) {
        entries.append(envelope)
        timestamps.append(Date())
        if snapshotSawExpectedMessage {
            self.snapshotSawExpectedMessage = true
        }
    }

    func didSnapshotSeeExpectedMessage() -> Bool {
        snapshotSawExpectedMessage
    }
}

private actor RestoreSessionRelayRegistrar: RemoteControlRelayRegistering {
    private(set) var startRequests: [RemoteControlPairStartRequest] = []
    private(set) var refreshRequests: [RemoteControlPairRefreshRequest] = []
    private(set) var stopRequests: [RemoteControlPairStopRequest] = []
    private(set) var listRequests: [RemoteControlDevicesListRequest] = []
    private(set) var revokeRequests: [RemoteControlDeviceRevokeRequest] = []
    private let listDevicesError: Error?

    init(listDevicesError: Error? = nil) {
        self.listDevicesError = listDevicesError
    }

    func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse {
        startRequests.append(request)
        return RemoteControlPairStartResponse(accepted: true, relayWebSocketURL: request.relayWebSocketURL)
    }

    func refreshPairing(_ request: RemoteControlPairRefreshRequest) async throws -> RemoteControlPairRefreshResponse {
        refreshRequests.append(request)
        return RemoteControlPairRefreshResponse(accepted: true, relayWebSocketURL: request.relayWebSocketURL)
    }

    func stopPairing(_ request: RemoteControlPairStopRequest) async throws -> RemoteControlPairStopResponse {
        stopRequests.append(request)
        return RemoteControlPairStopResponse(accepted: true)
    }

    func listDevices(_ request: RemoteControlDevicesListRequest) async throws -> RemoteControlDevicesListResponse {
        listRequests.append(request)
        if let listDevicesError {
            throw listDevicesError
        }
        return RemoteControlDevicesListResponse(accepted: true, devices: [])
    }

    func revokeDevice(_ request: RemoteControlDeviceRevokeRequest) async throws -> RemoteControlDeviceRevokeResponse {
        revokeRequests.append(request)
        return RemoteControlDeviceRevokeResponse(accepted: true)
    }
}

private final class InMemoryRemoteControlSessionCredentialStore: RemoteControlSessionCredentialStoring, @unchecked Sendable {
    private var descriptor: RemoteControlSessionDescriptor?

    init(descriptor: RemoteControlSessionDescriptor? = nil) {
        self.descriptor = descriptor
    }

    func loadSessionDescriptor() throws -> RemoteControlSessionDescriptor? {
        descriptor
    }

    func saveSessionDescriptor(_ descriptor: RemoteControlSessionDescriptor) throws {
        self.descriptor = descriptor
    }

    func clearSessionDescriptor() throws {
        descriptor = nil
    }
}

@MainActor
final class RemoteControlSyncTests: XCTestCase {
    func testRemoteThreadSendCommandWaitsForTranscriptBeforeSnapshotFlush() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-remote-command-sync-\(UUID().uuidString)", isDirectory: true)
        let projectURL = rootURL.appendingPathComponent("project", isDirectory: true)
        let dbURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let runtime = CodexRuntime(executableResolver: { nil })
        let model = AppModel(repositories: repositories, runtime: runtime, bootError: nil)

        let project = try await repositories.projectRepository.createProject(
            named: "Remote Sync",
            path: projectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Main"
        )

        model.projectsState = .loaded([project])
        model.threadsState = .loaded([thread])
        model.generalThreadsState = .loaded([])
        model.selectedProjectID = project.id
        model.selectedThreadID = thread.id
        model.runtimeStatus = .connected
        model.accountState = RuntimeAccountState(
            account: nil,
            authMode: .unknown,
            requiresOpenAIAuth: false
        )

        let now = Date()
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let session = RemoteControlSessionDescriptor(
            sessionID: "session-1",
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(120)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token",
            createdAt: now,
            idleTimeout: 120
        )
        model.remoteControlStatus = RemoteControlBrokerStatus(
            phase: .active,
            session: session,
            connectedDeviceCount: 1,
            disconnectReason: nil
        )
        model.remoteControlRelayAuthenticated = true

        let recorder = RemoteEnvelopeRecorder()
        model.remoteControlEnvelopeInterceptor = { [weak model] envelope in
            var snapshotContainsMessage = false
            if case .snapshot = envelope.payload, let model {
                snapshotContainsMessage = model.transcriptStore[thread.id, default: []].contains { entry in
                    guard case let .message(message) = entry else {
                        return false
                    }
                    return message.role == .user && message.text == "Ship the patch."
                }
            }
            await recorder.record(envelope, snapshotSawExpectedMessage: snapshotContainsMessage)
        }

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .threadSendMessage,
                commandID: "cmd-1",
                threadID: thread.id.uuidString,
                projectID: project.id.uuidString,
                text: "Ship the patch."
            ),
            inboundCommandSequence: 5
        )

        XCTAssertEqual(ack.status, .accepted)
        XCTAssertTrue(model.transcriptStore[thread.id, default: []].contains { entry in
            guard case let .message(message) = entry else {
                return false
            }
            return message.role == .user && message.text == "Ship the patch."
        })

        let envelopes = await recorder.entries
        XCTAssertTrue(envelopes.contains(where: {
            guard case .commandAck = $0.payload else { return false }
            return true
        }))
        XCTAssertTrue(envelopes.contains(where: {
            guard case .snapshot = $0.payload else { return false }
            return true
        }))
        let didSeeExpectedMessageInSnapshot = await recorder.didSnapshotSeeExpectedMessage()
        XCTAssertTrue(didSeeExpectedMessageInSnapshot)
    }

    func testAcceptedRemoteThreadSendPreservesLocalComposerDraftAndAttachments() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-preserve-local-draft")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        let attachmentURL = URL(fileURLWithPath: project.path, isDirectory: true)
            .appendingPathComponent("notes.txt", isDirectory: false)
        try Data("local attachment".utf8).write(to: attachmentURL, options: [.atomic])

        let draftAttachment = AppModel.ComposerAttachment(
            path: attachmentURL.path,
            name: attachmentURL.lastPathComponent,
            kind: .mentionFile
        )
        model.composerText = "preserve local draft"
        model.composerAttachments = [draftAttachment]

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .threadSendMessage,
                commandID: "cmd-preserve-local-draft",
                threadID: thread.id.uuidString,
                projectID: project.id.uuidString,
                text: "Ship the patch."
            ),
            inboundCommandSequence: 79
        )

        XCTAssertEqual(ack.status, .accepted)
        XCTAssertEqual(ack.threadID, thread.id.uuidString)
        XCTAssertEqual(model.composerText, "preserve local draft")
        XCTAssertEqual(model.composerAttachments, [draftAttachment])
        XCTAssertEqual(
            countUserMessages(
                in: model.transcriptStore[thread.id, default: []],
                text: "Ship the patch."
            ),
            1
        )
    }

    func testAssistantDeltaTriggersImmediateRemoteSyncWithoutPumpTick() async throws {
        let model = AppModel(
            repositories: nil,
            runtime: CodexRuntime(executableResolver: { nil }),
            bootError: nil
        )
        let threadID = UUID()
        let projectID = UUID()
        let project = ProjectRecord(
            id: projectID,
            name: "Remote",
            path: "/tmp/remote",
            isGeneralProject: false,
            trustState: .trusted,
            sandboxMode: .readOnly,
            approvalPolicy: .untrusted,
            networkAccess: false,
            webSearch: .cached,
            memoryWriteMode: .off,
            memoryEmbeddingsEnabled: false,
            uiModPath: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let thread = ThreadRecord(
            id: threadID,
            projectId: projectID,
            title: "Thread",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        model.projectsState = .loaded([project])
        model.threadsState = .loaded([thread])
        model.generalThreadsState = .loaded([])
        model.selectedProjectID = projectID
        model.selectedThreadID = threadID

        let now = Date()
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let session = RemoteControlSessionDescriptor(
            sessionID: "session-2",
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token-2",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(120)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token-2",
            createdAt: now,
            idleTimeout: 120
        )
        model.remoteControlStatus = RemoteControlBrokerStatus(
            phase: .active,
            session: session,
            connectedDeviceCount: 1,
            disconnectReason: nil
        )
        model.remoteControlRelayAuthenticated = true

        let recorder = RemoteEnvelopeRecorder()
        model.remoteControlEnvelopeInterceptor = { envelope in
            await recorder.record(envelope)
        }

        let start = Date()
        model.appendAssistantDelta("hello", itemID: "item-1", to: threadID)

        let didFlushQuickly = await waitUntil(timeoutSeconds: 0.45) {
            let envelopes = await recorder.entries
            return envelopes.contains(where: {
                guard case .snapshot = $0.payload else { return false }
                return true
            })
        }

        XCTAssertTrue(didFlushQuickly, "Expected an event-driven snapshot flush before the 700ms pump interval.")
        let envelopes = await recorder.entries
        let timestamps = await recorder.timestamps
        let snapshotIndex = try XCTUnwrap(envelopes.firstIndex(where: {
            guard case .snapshot = $0.payload else { return false }
            return true
        }))
        let snapshotTimestamp = timestamps[snapshotIndex]
        XCTAssertLessThan(snapshotTimestamp.timeIntervalSince(start), 0.45)
    }

    func testRemoteThreadSendCommandRejectsBusyWhenSelectedThreadAlreadyWorkingWithoutComposerMutation() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-busy-selected-thread-working")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        model.composerText = "preserve local draft"
        model.activeTurnThreadIDs = [thread.id]

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .threadSendMessage,
                commandID: "cmd-busy-selected-thread",
                threadID: thread.id.uuidString,
                projectID: project.id.uuidString,
                text: "Should reject while thread is working"
            ),
            inboundCommandSequence: 77
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "desktop_busy")
        XCTAssertEqual(ack.threadID, thread.id.uuidString)
        XCTAssertEqual(model.composerText, "preserve local draft")
        XCTAssertEqual(
            countUserMessages(
                in: model.transcriptStore[thread.id, default: []],
                text: "Should reject while thread is working"
            ),
            0
        )
    }

    func testRemoteThreadSendCommandRejectsBusyWhenGlobalCapacityWouldQueueWithoutComposerMutationOrQueueEnqueue() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-busy-global-capacity")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        model.composerText = "preserve local draft"
        let saturatedThreadIDs = Set((0 ..< AppModel.defaultMaxConcurrentTurns).map { _ in UUID() })
        XCTAssertFalse(saturatedThreadIDs.contains(thread.id))
        model.activeTurnThreadIDs = saturatedThreadIDs

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .threadSendMessage,
                commandID: "cmd-busy-global-capacity",
                threadID: thread.id.uuidString,
                projectID: project.id.uuidString,
                text: "Should reject while global capacity is saturated"
            ),
            inboundCommandSequence: 78
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "desktop_busy")
        XCTAssertEqual(ack.threadID, thread.id.uuidString)
        XCTAssertEqual(model.composerText, "preserve local draft")
        XCTAssertEqual(
            countUserMessages(
                in: model.transcriptStore[thread.id, default: []],
                text: "Should reject while global capacity is saturated"
            ),
            0
        )

        let didQueueFollowUp = await waitUntil(timeoutSeconds: 0.35) {
            await MainActor.run {
                !model.followUpQueueByThreadID[thread.id, default: []].isEmpty
            }
        }
        XCTAssertFalse(didQueueFollowUp, "Busy rejection should not enqueue follow-ups.")
    }

    func testDuplicateCommandAcrossRelayConnectionsReplaysAckWithoutReapplying() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-dup-ack-replay")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        let recorder = RemoteEnvelopeRecorder()
        model.remoteControlEnvelopeInterceptor = { envelope in
            await recorder.record(envelope)
        }

        let command = RemoteControlCommandPayload(
            name: .threadSendMessage,
            commandID: "cmd-dup-1",
            threadID: thread.id.uuidString,
            projectID: project.id.uuidString,
            text: "Apply exactly once"
        )
        let sessionID = try XCTUnwrap(model.remoteControlStatus.session?.sessionID)

        await model.handleRemoteControlEnvelope(
            RemoteControlEnvelope(
                sessionID: sessionID,
                seq: 11,
                payload: .command(command)
            ),
            relayConnectionID: "relay-connection-a"
        )
        await model.handleRemoteControlEnvelope(
            RemoteControlEnvelope(
                sessionID: sessionID,
                seq: 42,
                payload: .command(command)
            ),
            relayConnectionID: "relay-connection-b"
        )

        let messageCount = countUserMessages(
            in: model.transcriptStore[thread.id, default: []],
            text: "Apply exactly once"
        )
        XCTAssertEqual(messageCount, 1, "Duplicate replay should not apply the command twice.")

        let envelopes = await recorder.entries
        let ackPairs = indexedCommandAcks(envelopes) { ack in
            ack.commandID == "cmd-dup-1"
        }
        XCTAssertEqual(ackPairs.count, 2)
        XCTAssertEqual(ackPairs[0].ack.commandSeq, 11)
        XCTAssertEqual(ackPairs[1].ack, ackPairs[0].ack, "Duplicate replay should resend the cached ack payload.")

        let snapshotIndices = indexedSnapshots(envelopes)
        XCTAssertFalse(snapshotIndices.isEmpty)
        XCTAssertLessThan(ackPairs[0].index, snapshotIndices[0], "Accepted command ack should be sent before snapshot.")
        XCTAssertGreaterThan(ackPairs[1].index, snapshotIndices[0], "Replay ack should be sent when duplicate arrives.")
    }

    func testReusedCommandIDWithDifferentCommandShapeDoesNotReplayStaleAck() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-reused-command-id")
        let model = fixture.model
        let project = fixture.project

        let firstAck = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .projectSelect,
                commandID: "cmd-reused-1",
                projectID: project.id.uuidString
            ),
            inboundCommandSequence: 17
        )

        XCTAssertEqual(firstAck.status, .accepted)
        XCTAssertEqual(firstAck.commandName, .projectSelect)

        let secondAck = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .threadSelect,
                commandID: "cmd-reused-1",
                threadID: UUID().uuidString,
                projectID: project.id.uuidString
            ),
            inboundCommandSequence: 18
        )

        XCTAssertEqual(secondAck.status, .rejected)
        XCTAssertEqual(secondAck.commandName, .threadSelect)
        XCTAssertEqual(secondAck.reason, "unknown_thread")
        XCTAssertEqual(secondAck.commandSeq, 18)
    }

    func testThreadSendRejectsBlankCommandIDWithoutApplyingMessage() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-missing-command-id")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .threadSendMessage,
                commandID: "   ",
                threadID: thread.id.uuidString,
                projectID: project.id.uuidString,
                text: "Missing command ID should not send"
            ),
            inboundCommandSequence: 9
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "command_id_required")
        XCTAssertEqual(
            countUserMessages(
                in: model.transcriptStore[thread.id, default: []],
                text: "Missing command ID should not send"
            ),
            0
        )
    }

    func testStaleSequenceMalformedCommandWithBlankCommandIDReplaysRejectedAck() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-stale-missing-command-id")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        let recorder = RemoteEnvelopeRecorder()
        model.remoteControlEnvelopeInterceptor = { envelope in
            await recorder.record(envelope)
        }

        let command = RemoteControlCommandPayload(
            name: .threadSendMessage,
            commandID: " ",
            threadID: thread.id.uuidString,
            projectID: project.id.uuidString,
            text: "Missing command ID duplicate"
        )
        let sessionID = try XCTUnwrap(model.remoteControlStatus.session?.sessionID)

        await model.handleRemoteControlEnvelope(
            RemoteControlEnvelope(
                sessionID: sessionID,
                seq: 9,
                payload: .command(command)
            ),
            relayConnectionID: "relay-stale"
        )
        await model.handleRemoteControlEnvelope(
            RemoteControlEnvelope(
                sessionID: sessionID,
                seq: 9,
                payload: .command(command)
            ),
            relayConnectionID: "relay-stale"
        )

        let messageCount = countUserMessages(
            in: model.transcriptStore[thread.id, default: []],
            text: "Missing command ID duplicate"
        )
        XCTAssertEqual(messageCount, 0, "Malformed commands should not apply any remote send.")

        let envelopes = await recorder.entries
        let ackPairs = indexedCommandAcks(envelopes) { ack in
            ack.commandName == .threadSendMessage &&
                ack.threadID == thread.id.uuidString &&
                ack.reason == "command_id_required"
        }
        XCTAssertEqual(ackPairs.count, 2)
        XCTAssertEqual(ackPairs[0].ack.commandSeq, 9)
        XCTAssertEqual(ackPairs[0].ack.status, .rejected)
        XCTAssertEqual(ackPairs[1].ack, ackPairs[0].ack, "Stale malformed commands should replay the same rejected ack.")

        let snapshotIndices = indexedSnapshots(envelopes)
        XCTAssertTrue(snapshotIndices.isEmpty, "Rejected malformed commands should not force a snapshot.")
    }

    func testRuntimeRequestRespondRejectsMissingCommandID() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-approval-missing-command-id")
        let model = fixture.model
        model.allowRemoteApprovals = true

        let request = makeApprovalRequest(id: 41, threadID: fixture.thread.id)
        model.approvalStateMachine.enqueue(request, threadID: fixture.thread.id)
        model.syncApprovalPresentationState()

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "",
                runtimeRequestID: String(request.id),
                runtimeRequestKind: .approval,
                runtimeRequestResponse: .init(decision: "approve_once")
            ),
            inboundCommandSequence: 17
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "command_id_required")
        XCTAssertEqual(model.activeApprovalRequest?.id, request.id)
    }

    func testRuntimeRequestRespondRejectsMissingRequestID() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-approval-missing-request-id")
        let model = fixture.model
        model.allowRemoteApprovals = true

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "cmd-approval-missing-request",
                runtimeRequestKind: .approval,
                runtimeRequestResponse: .init(decision: "approve_once")
            ),
            inboundCommandSequence: 18
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "runtime_request_required")
    }

    func testRuntimeRequestRespondRejectsUnknownRequestID() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-approval-unknown-request-id")
        let model = fixture.model
        model.allowRemoteApprovals = true

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "cmd-approval-unknown-request",
                runtimeRequestID: "999",
                runtimeRequestKind: .approval,
                runtimeRequestResponse: .init(decision: "approve_once")
            ),
            inboundCommandSequence: 19
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "unknown_runtime_request")
    }

    func testRuntimeRequestRespondRejectsWhenDesktopIsOffline() async {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.allowRemoteApprovals = true

        let threadID = UUID()
        model.selectedThreadID = threadID
        let request = makeApprovalRequest(id: 42, threadID: threadID)
        model.approvalStateMachine.enqueue(request, threadID: threadID)
        model.syncApprovalPresentationState()

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "cmd-approval-offline",
                runtimeRequestID: String(request.id),
                runtimeRequestKind: .approval,
                runtimeRequestResponse: .init(decision: "approve_once")
            ),
            inboundCommandSequence: 20
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "desktop_offline")
        XCTAssertEqual(model.activeApprovalRequest?.id, request.id)
    }

    func testRuntimeRequestRespondPreservesLegacyDecisionAliases() async {
        let legacyDecisions = ["approve", "approve-once", "approve-session", "approveforsession", "reject"]

        for decision in legacyDecisions {
            let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
            model.allowRemoteApprovals = true

            let threadID = UUID()
            model.selectedThreadID = threadID
            let request = makeApprovalRequest(id: 420, threadID: threadID)
            model.approvalStateMachine.enqueue(request, threadID: threadID)
            model.syncApprovalPresentationState()

            let ack = await model.processRemoteControlCommand(
                RemoteControlCommandPayload(
                    name: .runtimeRequestRespond,
                    commandID: "cmd-approval-legacy-\(decision)",
                    runtimeRequestID: String(request.id),
                    runtimeRequestKind: .approval,
                    runtimeRequestResponse: .init(decision: decision)
                ),
                inboundCommandSequence: 200
            )

            XCTAssertEqual(ack.status, .rejected, "Offline runtime should reject legacy decision alias \(decision).")
            XCTAssertEqual(ack.reason, "desktop_offline", "Legacy decision alias \(decision) should still parse before runtime rejection.")
            XCTAssertEqual(model.activeApprovalRequest?.id, request.id)
        }
    }

    func testRuntimeRequestRespondRejectsWhenRuntimeCanNotApplyPendingApproval() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-approval-stale-runtime-route")
        let model = fixture.model
        model.allowRemoteApprovals = true

        let request = makeApprovalRequest(id: 43, threadID: fixture.thread.id)
        model.approvalStateMachine.enqueue(request, threadID: fixture.thread.id)
        model.syncApprovalPresentationState()

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "cmd-approval-stale-runtime-route",
                runtimeRequestID: String(request.id),
                runtimeRequestKind: .approval,
                runtimeRequestResponse: .init(decision: "approve_once")
            ),
            inboundCommandSequence: 21
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "unknown_runtime_request")
        XCTAssertEqual(model.activeApprovalRequest?.id, request.id)
    }

    func testRuntimeRequestRespondParsesPermissionsRequestBeforeDesktopOffline() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-runtime-request-permissions")
        let model = fixture.model
        model.allowRemoteApprovals = true

        let request = makePermissionsRequest(id: 91, threadID: fixture.thread.id)
        model.serverRequestStateMachine.enqueue(.permissions(request), threadID: fixture.thread.id)
        model.syncApprovalPresentationState()

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "cmd-runtime-request-permissions",
                runtimeRequestID: String(request.id),
                runtimeRequestKind: .permissionsApproval,
                runtimeRequestResponse: .init(
                    permissions: ["project.write"],
                    scope: "workspace"
                )
            ),
            inboundCommandSequence: 31
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "unknown_runtime_request")
    }

    func testRuntimeRequestRespondRejectsInvalidDynamicToolPayload() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-runtime-request-tool-invalid")
        let model = fixture.model
        model.allowRemoteApprovals = true

        let request = makeDynamicToolCallRequest(id: 92, threadID: fixture.thread.id)
        model.serverRequestStateMachine.enqueue(.dynamicToolCall(request), threadID: fixture.thread.id)
        model.syncApprovalPresentationState()

        let ack = await model.processRemoteControlCommand(
            RemoteControlCommandPayload(
                name: .runtimeRequestRespond,
                commandID: "cmd-runtime-request-tool-invalid",
                runtimeRequestID: String(request.id),
                runtimeRequestKind: .dynamicToolCall,
                runtimeRequestResponse: .init()
            ),
            inboundCommandSequence: 32
        )

        XCTAssertEqual(ack.status, .rejected)
        XCTAssertEqual(ack.reason, "invalid_runtime_request")
    }

    func testRestorePersistedRemoteControlSessionReconnectsWithoutPairRestart() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc#sid=session-resume&jt=join-token-resume"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let descriptor = RemoteControlSessionDescriptor(
            sessionID: "session-resume",
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token-resume",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(120)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token-resume",
            createdAt: now,
            idleTimeout: 1800
        )
        let credentialStore = InMemoryRemoteControlSessionCredentialStore(descriptor: descriptor)
        let registrar = RestoreSessionRelayRegistrar()
        let broker = RemoteControlBroker(relayRegistrar: registrar)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            remoteControlBroker: broker,
            remoteControlSessionCredentialStore: credentialStore
        )

        var connectedSessionIDs: [String] = []
        model.remoteControlWebSocketConnector = { sessionDescriptor in
            connectedSessionIDs.append(sessionDescriptor.sessionID)
        }

        await model.restorePersistedRemoteControlSessionIfNeeded()
        await model.restorePersistedRemoteControlSessionIfNeeded()

        XCTAssertEqual(model.remoteControlStatus.phase, .active)
        XCTAssertEqual(model.remoteControlStatus.session?.sessionID, descriptor.sessionID)
        XCTAssertEqual(connectedSessionIDs, [descriptor.sessionID], "Persisted restore should reconnect exactly once.")

        let pairStartRequests = await registrar.startRequests
        XCTAssertEqual(pairStartRequests.count, 0, "Restore should not call pair/start again.")
    }

    func testRestorePersistedRemoteControlSessionClearsExpiredCredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc#sid=session-expired&jt=join-token-expired"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let descriptor = RemoteControlSessionDescriptor(
            sessionID: "session-expired",
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token-expired",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(120)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token-expired",
            createdAt: now,
            idleTimeout: 1800
        )
        let credentialStore = InMemoryRemoteControlSessionCredentialStore(descriptor: descriptor)
        let invalidSessionError = NSError(
            domain: "CodexChat.RemoteControlRelay",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "session_not_found"]
        )
        let registrar = RestoreSessionRelayRegistrar(listDevicesError: invalidSessionError)
        let broker = RemoteControlBroker(relayRegistrar: registrar)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            remoteControlBroker: broker,
            remoteControlSessionCredentialStore: credentialStore
        )

        var didAttemptConnect = false
        model.remoteControlWebSocketConnector = { _ in
            didAttemptConnect = true
        }

        await model.restorePersistedRemoteControlSessionIfNeeded()

        XCTAssertFalse(didAttemptConnect, "Restore should not connect websocket when relay rejects session refresh.")
        XCTAssertEqual(model.remoteControlStatus.phase, .disconnected)
        XCTAssertEqual(model.remoteControlStatusMessage, "Session ended; start new session.")
        let clearedDescriptor = try credentialStore.loadSessionDescriptor()
        XCTAssertNil(clearedDescriptor, "Invalid persisted session should be cleared.")
    }

    func testRemoteControlSessionConnectionLabelReflectsRelayState() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-connection-label")
        let model = fixture.model

        model.remoteControlRelayAuthenticated = true
        model.remoteControlReconnectAttempt = 0
        XCTAssertEqual(model.remoteControlSessionConnectionLabel, "Connected")

        model.remoteControlRelayAuthenticated = false
        XCTAssertEqual(model.remoteControlSessionConnectionLabel, "Connecting")

        model.remoteControlReconnectAttempt = 1
        XCTAssertEqual(model.remoteControlSessionConnectionLabel, "Reconnecting")

        model.remoteControlStatus = RemoteControlBrokerStatus(
            phase: .disconnected,
            session: nil,
            connectedDeviceCount: 0,
            disconnectReason: "Stopped"
        )
        XCTAssertEqual(model.remoteControlSessionConnectionLabel, "Inactive")
    }

    func testPrepareForTeardownKeepsPersistedRemoteSessionAndDoesNotStopRelaySession() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_200)
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc#sid=session-teardown&jt=join-token-teardown"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let descriptor = RemoteControlSessionDescriptor(
            sessionID: "session-teardown",
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token-teardown",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(120)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token-teardown",
            createdAt: now,
            idleTimeout: 1800
        )
        let credentialStore = InMemoryRemoteControlSessionCredentialStore(descriptor: descriptor)
        let registrar = RestoreSessionRelayRegistrar()
        let broker = RemoteControlBroker(relayRegistrar: registrar)
        await broker.restoreSession(descriptor)

        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            remoteControlBroker: broker,
            remoteControlSessionCredentialStore: credentialStore
        )
        model.remoteControlStatus = await broker.currentStatus()

        model.prepareForTeardown()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let stopRequests = await registrar.stopRequests
        XCTAssertEqual(stopRequests.count, 0, "Normal app teardown should not end relay session.")

        let persistedDescriptor = try credentialStore.loadSessionDescriptor()
        XCTAssertEqual(
            persistedDescriptor,
            descriptor,
            "Persisted remote session should remain available across desktop restarts."
        )
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return await condition()
    }

    private func makeRemoteCommandFixture(
        sessionID: String
    ) async throws -> (model: AppModel, project: ProjectRecord, thread: ThreadRecord) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-remote-command-sync-\(UUID().uuidString)", isDirectory: true)
        let projectURL = rootURL.appendingPathComponent("project", isDirectory: true)
        let dbURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: CodexRuntime(executableResolver: { nil }),
            bootError: nil
        )

        let project = try await repositories.projectRepository.createProject(
            named: "Remote Sync",
            path: projectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Main"
        )

        model.projectsState = .loaded([project])
        model.threadsState = .loaded([thread])
        model.generalThreadsState = .loaded([])
        model.selectedProjectID = project.id
        model.selectedThreadID = thread.id
        model.runtimeStatus = .connected
        model.accountState = RuntimeAccountState(
            account: nil,
            authMode: .unknown,
            requiresOpenAIAuth: false
        )

        let now = Date()
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let session = RemoteControlSessionDescriptor(
            sessionID: sessionID,
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token-\(sessionID)",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(120)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token-\(sessionID)",
            createdAt: now,
            idleTimeout: 120
        )
        model.remoteControlStatus = RemoteControlBrokerStatus(
            phase: .active,
            session: session,
            connectedDeviceCount: 1,
            disconnectReason: nil
        )
        model.remoteControlRelayAuthenticated = true

        return (model, project, thread)
    }

    private func countUserMessages(
        in entries: [TranscriptEntry],
        text: String
    ) -> Int {
        entries.reduce(into: 0) { partialResult, entry in
            guard case let .message(message) = entry,
                  message.role == .user,
                  message.text == text
            else {
                return
            }
            partialResult += 1
        }
    }

    private func indexedCommandAcks(
        _ envelopes: [RemoteControlEnvelope],
        where predicate: (RemoteControlCommandAckPayload) -> Bool
    ) -> [(index: Int, ack: RemoteControlCommandAckPayload)] {
        envelopes.enumerated().compactMap { index, envelope in
            guard case let .commandAck(ack) = envelope.payload,
                  predicate(ack)
            else {
                return nil
            }
            return (index, ack)
        }
    }

    private func indexedSnapshots(_ envelopes: [RemoteControlEnvelope]) -> [Int] {
        envelopes.enumerated().compactMap { index, envelope in
            guard case .snapshot = envelope.payload else {
                return nil
            }
            return index
        }
    }

    private func makeApprovalRequest(id: Int, threadID: UUID) -> RuntimeApprovalRequest {
        RuntimeApprovalRequest(
            id: id,
            kind: .commandExecution,
            method: "shell",
            threadID: threadID.uuidString,
            turnID: nil,
            itemID: nil,
            reason: "Need approval",
            risk: "medium",
            cwd: "/tmp",
            command: ["/bin/echo", "hello"],
            changes: [],
            detail: "Approval detail"
        )
    }

    private func makePermissionsRequest(id: Int, threadID: UUID) -> RuntimePermissionsRequest {
        RuntimePermissionsRequest(
            id: id,
            method: "item/permissions/requestApproval",
            threadID: threadID.uuidString,
            turnID: nil,
            itemID: nil,
            reason: "Need write access",
            cwd: "/tmp",
            permissions: ["project.write"],
            grantRoot: "workspace",
            detail: "Need project.write"
        )
    }

    private func makeDynamicToolCallRequest(id: Int, threadID: UUID) -> RuntimeDynamicToolCallRequest {
        RuntimeDynamicToolCallRequest(
            id: id,
            method: "item/tool/call",
            threadID: threadID.uuidString,
            turnID: nil,
            itemID: nil,
            toolName: "browser.click",
            arguments: nil,
            detail: "Dynamic tool call"
        )
    }
}
