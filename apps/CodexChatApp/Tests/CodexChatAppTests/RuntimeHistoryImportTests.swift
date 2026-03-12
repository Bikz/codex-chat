import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

@MainActor
final class RuntimeHistoryImportTests: XCTestCase {
    func testThreadSummariesDecodeDataPayloadAndSkipEphemeralThreads() {
        let payload: JSONValue = .object([
            "data": .array([
                .object([
                    "id": .string("thr-1"),
                    "name": .string("Project cleanup"),
                    "preview": .string("Tighten onboarding"),
                    "createdAt": .number(1_773_291_409),
                    "updatedAt": .number(1_773_291_556),
                    "cwd": .string("/tmp/project"),
                    "source": .string("vscode"),
                    "ephemeral": .bool(false),
                ]),
                .object([
                    "id": .string("thr-temp"),
                    "preview": .string("Ignore me"),
                    "ephemeral": .bool(true),
                ]),
            ]),
        ])

        let summaries = RuntimeHistoryImportParser.threadSummaries(from: payload)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.runtimeThreadID, "thr-1")
        XCTAssertEqual(summaries.first?.title, "Project cleanup")
        XCTAssertEqual(summaries.first?.preview, "Tighten onboarding")
        XCTAssertEqual(summaries.first?.cwd, "/tmp/project")
        XCTAssertEqual(summaries.first?.source, "vscode")
    }

    func testImportedThreadDecodesTurnTextAndMetadataAction() {
        let fallback = RuntimeHistoryThreadSummary(
            runtimeThreadID: "thr-1",
            title: "Fallback",
            preview: "Fallback preview",
            createdAt: nil,
            updatedAt: nil,
            cwd: "/Users/bikram/Developer/CodexChat",
            source: "vscode"
        )
        let payload: JSONValue = .object([
            "thread": .object([
                "name": .string("Imported thread"),
                "preview": .string("Preview text"),
                "turns": .array([
                    .object([
                        "createdAt": .number(1_773_291_409),
                        "items": .array([
                            .object([
                                "type": .string("userMessage"),
                                "content": .array([
                                    .object([
                                        "type": .string("text"),
                                        "text": .string("Please simplify the dashboard"),
                                    ]),
                                ]),
                            ]),
                            .object([
                                "type": .string("assistantMessage"),
                                "content": .array([
                                    .object([
                                        "type": .string("text"),
                                        "text": .string("I'd remove the mast dashboard for MVP."),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])

        let imported = RuntimeHistoryImportParser.importedThread(from: payload, fallback: fallback)

        XCTAssertEqual(imported.title, "Imported thread")
        XCTAssertEqual(imported.turns.count, 1)
        XCTAssertEqual(imported.turns.first?.userText, "Please simplify the dashboard")
        XCTAssertEqual(imported.turns.first?.assistantText, "I'd remove the mast dashboard for MVP.")
        XCTAssertEqual(imported.turns.first?.actions.first?.title, "Imported from Codex")
        XCTAssertTrue(imported.turns.first?.actions.first?.detail.contains("Workspace: /Users/bikram/Developer/CodexChat") == true)
    }

    func testOnboardingWaitsForRuntimeHistoryImportDecision() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-runtime-history-import-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()
        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: paths,
            resolvedCodexHomes: makeTestResolvedCodexHomes(root: root, storagePaths: paths)
        )

        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(type: "chatgpt", name: "Tester", email: nil, planType: nil),
            authMode: .chatGPT,
            requiresOpenAIAuth: true
        )
        model.runtimeStatus = .connected
        model.runtimeIssue = nil

        model.runtimeHistoryImportState = .available(threadCount: 3)
        XCTAssertFalse(model.isOnboardingReadyToComplete)

        model.runtimeHistoryImportState = .idle
        XCTAssertTrue(model.isOnboardingReadyToComplete)
    }
}
