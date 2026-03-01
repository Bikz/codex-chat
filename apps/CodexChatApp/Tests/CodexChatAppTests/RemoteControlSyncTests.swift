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

    func testStaleSequenceDuplicateWithFallbackIdentityReplaysCachedAck() async throws {
        let fixture = try await makeRemoteCommandFixture(sessionID: "session-stale-ack-replay")
        let model = fixture.model
        let thread = fixture.thread
        let project = fixture.project

        let recorder = RemoteEnvelopeRecorder()
        model.remoteControlEnvelopeInterceptor = { envelope in
            await recorder.record(envelope)
        }

        let command = RemoteControlCommandPayload(
            name: .threadSendMessage,
            threadID: thread.id.uuidString,
            projectID: project.id.uuidString,
            text: "Fallback identity command"
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
            text: "Fallback identity command"
        )
        XCTAssertEqual(messageCount, 1, "Stale duplicate should not reapply the command.")

        let envelopes = await recorder.entries
        let ackPairs = indexedCommandAcks(envelopes) { ack in
            ack.commandName == .threadSendMessage &&
                ack.threadID == thread.id.uuidString &&
                ack.commandID == nil
        }
        XCTAssertEqual(ackPairs.count, 2)
        XCTAssertEqual(ackPairs[0].ack.commandSeq, 9)
        XCTAssertEqual(ackPairs[1].ack, ackPairs[0].ack, "Stale duplicate should replay the cached ack payload.")

        let snapshotIndices = indexedSnapshots(envelopes)
        XCTAssertFalse(snapshotIndices.isEmpty)
        XCTAssertLessThan(ackPairs[0].index, snapshotIndices[0], "Initial accepted ack should precede snapshot.")
        XCTAssertGreaterThan(ackPairs[1].index, snapshotIndices[0], "Stale replay ack should be emitted when duplicate arrives.")
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
}
