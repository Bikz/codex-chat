import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexKit
import CodexMemory
import CodexMods
import XCTest

final class CodexChatAppTests: XCTestCase {
    func testChatArchiveAppendAndRevealLookup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-archive-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let summary = ArchivedTurnSummary(
            timestamp: Date(),
            userText: "Please update the README.",
            assistantText: "Done. README updated.",
            actions: []
        )

        let archiveURL = try ChatArchiveStore.appendTurn(
            projectPath: root.path,
            threadID: threadID,
            turn: summary
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let content = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Please update the README."))
        XCTAssertTrue(content.contains("Done. README updated."))

        let latest = ChatArchiveStore.latestArchiveURL(projectPath: root.path, threadID: threadID)
        XCTAssertEqual(
            latest?.resolvingSymlinksInPath().path,
            archiveURL.resolvingSymlinksInPath().path
        )
    }

    func testChatArchiveAppendPreservesPriorTurns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-archive-multi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(60)

        _ = try ChatArchiveStore.appendTurn(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                timestamp: t0,
                userText: "First question",
                assistantText: "First answer",
                actions: []
            )
        )

        let archiveURL = try ChatArchiveStore.appendTurn(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                timestamp: t1,
                userText: "Second question",
                assistantText: "Second answer",
                actions: []
            )
        )

        let content = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertEqual(
            content.components(separatedBy: "# Thread Transcript for \(threadID.uuidString)").count - 1,
            1
        )
        XCTAssertTrue(content.contains("First question"))
        XCTAssertTrue(content.contains("First answer"))
        XCTAssertTrue(content.contains("Second question"))
        XCTAssertTrue(content.contains("Second answer"))
    }

    @MainActor
    func testLaunchHealthCheckRepairsExistingProjectAndRecoversSelectionFromMissingPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-launch-health-\(UUID().uuidString)", isDirectory: true)
        let healthyURL = root.appendingPathComponent("healthy-project", isDirectory: true)
        let missingURL = root.appendingPathComponent("missing-project", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)

        try FileManager.default.createDirectory(at: healthyURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let missingProject = try await repositories.projectRepository.createProject(
            named: "Missing",
            path: missingURL.path,
            trustState: .untrusted,
            isGeneralProject: false
        )
        let healthyProject = try await repositories.projectRepository.createProject(
            named: "Healthy",
            path: healthyURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let staleThread = try await repositories.threadRepository.createThread(
            projectID: missingProject.id,
            title: "Stale thread"
        )

        try await repositories.preferenceRepository.setPreference(
            key: .lastOpenedProjectID,
            value: missingProject.id.uuidString
        )
        try await repositories.preferenceRepository.setPreference(
            key: .lastOpenedThreadID,
            value: staleThread.id.uuidString
        )

        try await model.refreshProjects()
        try await model.restoreLastOpenedContext()
        XCTAssertEqual(model.selectedProjectID, missingProject.id)
        XCTAssertEqual(model.selectedThreadID, staleThread.id)

        try await model.validateAndRepairProjectsOnLaunch()

        XCTAssertEqual(model.selectedProjectID, healthyProject.id)
        XCTAssertNil(model.selectedThreadID)
        XCTAssertTrue(model.projectStatusMessage?.contains("not found") ?? false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: healthyURL.appendingPathComponent("chats").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: healthyURL.appendingPathComponent("artifacts").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: healthyURL.appendingPathComponent("mods").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: healthyURL.appendingPathComponent(".agents/skills").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: healthyURL.appendingPathComponent("memory/profile.md").path))

        let persistedProjectID = try await repositories.preferenceRepository.getPreference(key: .lastOpenedProjectID)
        let persistedThreadID = try await repositories.preferenceRepository.getPreference(key: .lastOpenedThreadID)
        XCTAssertEqual(persistedProjectID, healthyProject.id.uuidString)
        XCTAssertEqual(persistedThreadID, "")
    }

    func testApprovalStateMachineQueuesAndResolvesInOrder() {
        var state = ApprovalStateMachine()
        let first = makeApprovalRequest(id: 1)
        let second = makeApprovalRequest(id: 2)

        state.enqueue(first)
        state.enqueue(second)

        XCTAssertEqual(state.activeRequest?.id, 1)
        XCTAssertEqual(state.queuedRequests.map(\.id), [2])

        _ = state.resolve(id: 1)
        XCTAssertEqual(state.activeRequest?.id, 2)
        XCTAssertTrue(state.queuedRequests.isEmpty)

        _ = state.resolve(id: 2)
        XCTAssertNil(state.activeRequest)
        XCTAssertFalse(state.hasPendingApprovals)
    }

    func testApprovalStateMachineIgnoresDuplicateRequests() {
        var state = ApprovalStateMachine()
        let request = makeApprovalRequest(id: 42)

        state.enqueue(request)
        state.enqueue(request)

        XCTAssertEqual(state.activeRequest?.id, 42)
        XCTAssertTrue(state.queuedRequests.isEmpty)
    }

    @MainActor
    func testRuntimeTerminationResetsPendingApprovalWithExplicitMessage() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let projectID = UUID()
        let request = makeApprovalRequest(id: 101)
        model.selectedThreadID = threadID
        model.activeTurnContext = AppModel.ActiveTurnContext(
            localTurnID: UUID(),
            localThreadID: threadID,
            projectID: projectID,
            projectPath: "/tmp",
            runtimeThreadID: "thr_1",
            memoryWriteMode: .off,
            userText: "hello",
            assistantText: "",
            actions: [],
            startedAt: Date()
        )
        model.approvalStateMachine.enqueue(request)
        model.activeApprovalRequest = model.approvalStateMachine.activeRequest
        model.isApprovalDecisionInProgress = true

        model.handleRuntimeTermination(detail: "Simulated runtime crash.")

        XCTAssertFalse(model.approvalStateMachine.hasPendingApprovals)
        XCTAssertNil(model.activeApprovalRequest)
        XCTAssertFalse(model.isApprovalDecisionInProgress)
        XCTAssertTrue(model.approvalStatusMessage?.contains("Approval request was reset") ?? false)

        let entries = model.transcriptStore[threadID, default: []]
        let approvalResetCardExists = entries.contains { entry in
            guard case let .actionCard(card) = entry else {
                return false
            }
            return card.method == "approval/reset" && card.title == "Approval reset"
        }
        XCTAssertTrue(approvalResetCardExists)
    }

    @MainActor
    func testAccountDisplayNamePrefersRuntimeNameWhenPresent() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(
                type: "chatgpt",
                name: "Bikram Brar",
                email: "bikram@example.com",
                planType: "pro"
            ),
            authMode: .chatGPT,
            requiresOpenAIAuth: true
        )

        XCTAssertEqual(model.accountDisplayName, "Bikram Brar")
    }

    @MainActor
    func testAccountDisplayNameFallsBackToEmailWhenNameMissingOrEmpty() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(
                type: "chatgpt",
                name: "   ",
                email: "bikram@example.com",
                planType: "pro"
            ),
            authMode: .chatGPT,
            requiresOpenAIAuth: true
        )

        XCTAssertEqual(model.accountDisplayName, "bikram@example.com")
    }

    @MainActor
    func testAccountDisplayNameFallsBackToAccountWhenNameAndEmailMissing() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(
                type: "chatgpt",
                name: nil,
                email: nil,
                planType: nil
            ),
            authMode: .chatGPT,
            requiresOpenAIAuth: true
        )

        XCTAssertEqual(model.accountDisplayName, "Account")
    }

    @MainActor
    func testLoadCodexConfigMigratesLegacyRuntimeDefaults() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-runtime-defaults-\(UUID().uuidString)", isDirectory: true)
        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let safety = ProjectSafetySettings(
            sandboxMode: .workspaceWrite,
            approvalPolicy: .onRequest,
            networkAccess: true,
            webSearch: .live
        )

        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultModel,
            value: "gpt-5"
        )
        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultReasoning,
            value: AppModel.ReasoningLevel.high.rawValue
        )
        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultWebSearch,
            value: ProjectWebSearchMode.disabled.rawValue
        )
        let encodedSafety = try JSONEncoder().encode(safety)
        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultSafety,
            value: String(decoding: encodedSafety, as: UTF8.self)
        )

        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )
        try await model.loadCodexConfig()

        XCTAssertEqual(model.defaultModel, "gpt-5")
        XCTAssertEqual(model.defaultReasoning, .high)
        XCTAssertEqual(model.defaultWebSearch, .disabled)
        XCTAssertEqual(
            model.defaultSafetySettings,
            ProjectSafetySettings(
                sandboxMode: .workspaceWrite,
                approvalPolicy: .onRequest,
                networkAccess: true,
                webSearch: .disabled
            )
        )
        let migrationMarker = try await repositories.preferenceRepository.getPreference(key: .runtimeConfigMigrationV1)
        XCTAssertEqual(migrationMarker, "1")

        let migratedDocument = try CodexConfigDocument.parse(
            rawText: String(contentsOf: storagePaths.codexConfigURL, encoding: .utf8)
        )
        XCTAssertEqual(migratedDocument.value(at: [.key("model")])?.stringValue, "gpt-5")
        XCTAssertEqual(migratedDocument.value(at: [.key("model_reasoning_effort")])?.stringValue, "high")
        XCTAssertEqual(migratedDocument.value(at: [.key("web_search")])?.stringValue, "disabled")
        XCTAssertEqual(migratedDocument.value(at: [.key("sandbox_mode")])?.stringValue, "workspace-write")
        XCTAssertEqual(migratedDocument.value(at: [.key("approval_policy")])?.stringValue, "on-request")
        XCTAssertEqual(
            migratedDocument.value(at: [.key("sandbox_workspace_write"), .key("network_access")])?.booleanValue,
            true
        )
    }

    @MainActor
    func testLoadCodexConfigMigrationUsesSafetyWebSearchWhenLegacyWebSearchMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-runtime-defaults-fallback-\(UUID().uuidString)", isDirectory: true)
        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let safety = ProjectSafetySettings(
            sandboxMode: .workspaceWrite,
            approvalPolicy: .onRequest,
            networkAccess: true,
            webSearch: .live
        )

        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultModel,
            value: "gpt-5"
        )
        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultReasoning,
            value: AppModel.ReasoningLevel.high.rawValue
        )
        let encodedSafety = try JSONEncoder().encode(safety)
        try await repositories.preferenceRepository.setPreference(
            key: .runtimeDefaultSafety,
            value: String(decoding: encodedSafety, as: UTF8.self)
        )

        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )
        try await model.loadCodexConfig()

        XCTAssertEqual(model.defaultModel, "gpt-5")
        XCTAssertEqual(model.defaultReasoning, .high)
        XCTAssertEqual(model.defaultWebSearch, .live)
        XCTAssertEqual(model.defaultSafetySettings, safety)

        let migratedDocument = try CodexConfigDocument.parse(
            rawText: String(contentsOf: storagePaths.codexConfigURL, encoding: .utf8)
        )
        XCTAssertEqual(migratedDocument.value(at: [.key("web_search")])?.stringValue, "live")
    }

    @MainActor
    func testSaveCodexConfigAndRestartRuntimeShowsNextStartMessageWhenRuntimeUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-save-config-\(UUID().uuidString)", isDirectory: true)
        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )
        model.updateCodexConfigValue(path: [.key("model")], value: .string("custom-model"))

        await model.saveCodexConfigAndRestartRuntime()

        XCTAssertEqual(model.codexConfigStatusMessage, "Saved config.toml. Changes apply on next runtime start.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storagePaths.codexConfigURL.path))
    }

    @MainActor
    func testConfigDerivedDefaultsResetWhenKeysRemoved() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        model.updateCodexConfigValue(path: [.key("model")], value: .string("gpt-5"))
        model.updateCodexConfigValue(path: [.key("model_reasoning_effort")], value: .string("high"))
        model.updateCodexConfigValue(path: [.key("web_search")], value: .string("live"))

        XCTAssertEqual(model.defaultModel, "gpt-5")
        XCTAssertEqual(model.defaultReasoning, .high)
        XCTAssertEqual(model.defaultWebSearch, .live)

        model.updateCodexConfigValue(path: [.key("model")], value: nil)
        model.updateCodexConfigValue(path: [.key("model_reasoning_effort")], value: nil)
        model.updateCodexConfigValue(path: [.key("web_search")], value: nil)

        XCTAssertEqual(model.defaultModel, "")
        XCTAssertEqual(model.defaultReasoning, .medium)
        XCTAssertEqual(model.defaultWebSearch, .cached)
    }

    @MainActor
    func testConfigDerivedDefaultsUseRuntimeModelCatalogWhenModelUnset() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.runtimeModelCatalog = [
            RuntimeModelInfo(
                id: "gpt-5.3-codex",
                model: "gpt-5.3-codex",
                displayName: "GPT-5.3 Codex",
                supportedReasoningEfforts: [
                    RuntimeReasoningEffortOption(reasoningEffort: "low"),
                    RuntimeReasoningEffortOption(reasoningEffort: "medium"),
                    RuntimeReasoningEffortOption(reasoningEffort: "high"),
                    RuntimeReasoningEffortOption(reasoningEffort: "xhigh"),
                ],
                defaultReasoningEffort: "xhigh",
                isDefault: true
            ),
        ]

        model.replaceCodexConfigDocument(.empty())

        XCTAssertEqual(model.defaultModel, "gpt-5.3-codex")
        XCTAssertTrue(model.isUsingRuntimeDefaultModel)
        XCTAssertEqual(model.defaultReasoning, .xhigh)
        XCTAssertNil(model.runtimeTurnOptions().model)
    }

    @MainActor
    func testReasoningLevelsClampToSelectedModelCapabilities() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.runtimeModelCatalog = [
            RuntimeModelInfo(
                id: "gpt-5.1-codex-mini",
                model: "gpt-5.1-codex-mini",
                displayName: "GPT-5.1 Codex Mini",
                supportedReasoningEfforts: [
                    RuntimeReasoningEffortOption(reasoningEffort: "medium"),
                    RuntimeReasoningEffortOption(reasoningEffort: "high"),
                ],
                defaultReasoningEffort: "medium",
                isDefault: false
            ),
        ]

        model.updateCodexConfigValue(path: [.key("model")], value: .string("gpt-5.1-codex-mini"))
        model.updateCodexConfigValue(path: [.key("model_reasoning_effort")], value: .string("low"))

        XCTAssertEqual(model.reasoningPresets, [.medium, .high])
        XCTAssertEqual(model.defaultReasoning, .medium)
    }

    @MainActor
    func testLoadInitialDataContinuesWhenConfigTomlInvalid() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-invalid-config-\(UUID().uuidString)", isDirectory: true)
        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()
        defer { try? FileManager.default.removeItem(at: root) }

        try "model = [".write(to: storagePaths.codexConfigURL, atomically: true, encoding: .utf8)

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )

        await model.loadInitialData()

        if case let .failed(message) = model.projectsState {
            XCTFail("Expected startup to continue with invalid config.toml, but projects failed: \(message)")
        }

        XCTAssertEqual(model.defaultModel, "")
        XCTAssertEqual(model.defaultReasoning, .medium)
        XCTAssertEqual(model.defaultWebSearch, .cached)
        XCTAssertTrue(model.codexConfigStatusMessage?.contains("Failed to load config.toml. Using built-in defaults") ?? false)
    }

    @MainActor
    func testEffectiveWebSearchModeClampsToProjectPolicy() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        XCTAssertEqual(model.effectiveWebSearchMode(preferred: .live, projectPolicy: .cached), .cached)
        XCTAssertEqual(model.effectiveWebSearchMode(preferred: .live, projectPolicy: .disabled), .disabled)
        XCTAssertEqual(model.effectiveWebSearchMode(preferred: .disabled, projectPolicy: .live), .disabled)
    }

    @MainActor
    func testShouldRetryWithoutTurnOptionsForUnsupportedModelOrReasoning() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        XCTAssertTrue(
            model.shouldRetryWithoutTurnOptions(
                CodexRuntimeError.rpcError(code: -32602, message: "Unknown model: custom-model")
            )
        )
        XCTAssertTrue(
            model.shouldRetryWithoutTurnOptions(
                CodexRuntimeError.rpcError(code: -32602, message: "Invalid effort value")
            )
        )
        XCTAssertTrue(
            model.shouldRetryWithoutTurnOptions(
                CodexRuntimeError.rpcError(code: -32600, message: "unsupported value for reasoning.effort")
            )
        )
        XCTAssertFalse(
            model.shouldRetryWithoutTurnOptions(
                CodexRuntimeError.rpcError(code: -32601, message: "Unknown method")
            )
        )
    }

    @MainActor
    func testUnreadThreadStateMarksOnRuntimeUpdatesAndClearsOnSelection() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let selectedThreadID = UUID()
        let activeThreadID = UUID()

        model.selectedThreadID = selectedThreadID
        model.isTurnInProgress = true
        model.activeTurnContext = AppModel.ActiveTurnContext(
            localTurnID: UUID(),
            localThreadID: activeThreadID,
            projectID: UUID(),
            projectPath: "/tmp",
            runtimeThreadID: "thr_active",
            runtimeTurnID: "turn_active",
            memoryWriteMode: .off,
            userText: "Start work",
            assistantText: "",
            actions: [],
            startedAt: Date()
        )

        model.handleRuntimeEvent(.assistantMessageDelta(itemID: "msg_1", delta: "Working"))
        XCTAssertTrue(model.isThreadUnread(activeThreadID))
        XCTAssertTrue(model.isThreadWorking(activeThreadID))
        XCTAssertFalse(model.isThreadUnread(selectedThreadID))

        model.handleRuntimeEvent(
            .turnCompleted(
                RuntimeTurnCompletion(
                    turnID: "turn_active",
                    status: "completed",
                    errorMessage: nil
                )
            )
        )
        XCTAssertTrue(model.isThreadUnread(activeThreadID))

        model.selectedThreadID = activeThreadID
        XCTAssertFalse(model.isThreadUnread(activeThreadID))
    }

    func testMemoryAutoSummaryFormattingRespectsMode() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let threadID = UUID()
        let userText = "Remember that I prefer SwiftUI."
        let assistantText = """
        Sure.
        - Prefer SwiftUI for UI work
        - Keep docs private
        """

        let markdownSummariesOnly = MemoryAutoSummary.markdown(
            timestamp: timestamp,
            threadID: threadID,
            userText: userText,
            assistantText: assistantText,
            actions: [
                ActionCard(threadID: threadID, method: "tool/run", title: "Ran command", detail: "echo hello"),
            ],
            mode: .summariesOnly
        )
        XCTAssertFalse(markdownSummariesOnly.contains("Key facts"))

        let markdownWithFacts = MemoryAutoSummary.markdown(
            timestamp: timestamp,
            threadID: threadID,
            userText: userText,
            assistantText: assistantText,
            actions: [],
            mode: .summariesAndKeyFacts
        )
        XCTAssertTrue(markdownWithFacts.contains("Key facts"))
        XCTAssertTrue(markdownWithFacts.contains("Prefer SwiftUI"))
    }

    @MainActor
    func testSteerFailureMarksQueuedItemFailed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-followup-failure-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Failure Project",
            path: root.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Failure Thread"
        )

        let item = FollowUpQueueItemRecord(
            threadID: thread.id,
            source: .userQueued,
            dispatchMode: .auto,
            text: "Will fail",
            sortIndex: 0
        )
        try await repositories.followUpQueueRepository.enqueue(item)

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        model.selectedProjectID = project.id
        model.selectedThreadID = thread.id
        model.runtimeStatus = .connected
        try await model.refreshFollowUpQueue(threadID: thread.id)

        model.steerFollowUp(item.id)

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if let failed = model.selectedFollowUpQueueItems.first(where: { $0.id == item.id }) {
                if failed.state == .failed {
                    XCTAssertNotNil(failed.lastError)
                    return
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Expected queued item to transition to failed state")
    }

    func testResolvedThemeOverridesPreferProjectThemeForLightMode() {
        let globalMod = makeMod(
            path: "/global/green",
            theme: ModThemeOverride(
                typography: .init(titleSize: 20, bodySize: 13, captionSize: 11),
                palette: .init(accentHex: "#2E7D32", backgroundHex: "#F1F3F1", panelHex: "#FAFFFA")
            )
        )
        let projectMod = makeMod(
            scope: .project,
            path: "/project/orange",
            theme: ModThemeOverride(
                typography: .init(titleSize: nil, bodySize: 15, captionSize: nil),
                palette: .init(accentHex: "#FF5500", backgroundHex: nil, panelHex: "#FFF4EE")
            )
        )

        let resolved = AppModel.resolvedThemeOverrides(
            globalMods: [globalMod],
            projectMods: [projectMod],
            selectedGlobalPath: "/global/green",
            selectedProjectPath: "/project/orange"
        )

        XCTAssertEqual(resolved.light.palette?.accentHex, "#FF5500")
        XCTAssertEqual(resolved.light.palette?.backgroundHex, "#F1F3F1")
        XCTAssertEqual(resolved.light.palette?.panelHex, "#FFF4EE")
        XCTAssertEqual(resolved.light.typography?.bodySize, 15)
    }

    func testResolvedThemeOverridesDarkFallbackStripsLightColorsWithoutDarkTheme() {
        let globalMod = makeMod(
            path: "/global/light-only",
            theme: ModThemeOverride(
                typography: .init(titleSize: 21, bodySize: 16, captionSize: 12),
                palette: .init(accentHex: "#10A37F", backgroundHex: "#F7F8F7", panelHex: "#FFFFFF"),
                materials: .init(panelMaterial: "thin", cardMaterial: "regular"),
                bubbles: .init(style: "solid", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#FFFFFF")
            )
        )

        let resolved = AppModel.resolvedThemeOverrides(
            globalMods: [globalMod],
            projectMods: [],
            selectedGlobalPath: "/global/light-only",
            selectedProjectPath: nil
        )

        XCTAssertNil(resolved.dark.resolvedPaletteAccentHex)
        XCTAssertNil(resolved.dark.resolvedPaletteBackgroundHex)
        XCTAssertNil(resolved.dark.resolvedPalettePanelHex)
        XCTAssertNil(resolved.dark.bubbles?.userBackgroundHex)
        XCTAssertNil(resolved.dark.bubbles?.assistantBackgroundHex)
        XCTAssertEqual(resolved.dark.bubbles?.style, "solid")
        XCTAssertEqual(resolved.dark.typography?.bodySize, 16)
        XCTAssertEqual(resolved.dark.materials?.panelMaterial, "thin")
    }

    func testResolvedThemeOverridesDarkThemeOverridesFallbackColors() {
        let globalMod = makeMod(
            path: "/global/dual-theme",
            theme: ModThemeOverride(
                typography: .init(titleSize: 21, bodySize: 14, captionSize: 12),
                palette: .init(accentHex: "#10A37F", backgroundHex: "#F7F8F7", panelHex: "#FFFFFF"),
                bubbles: .init(style: "solid", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#FFFFFF")
            ),
            darkTheme: ModThemeOverride(
                palette: .init(accentHex: "#10A37F", backgroundHex: "#000000", panelHex: "#121212"),
                bubbles: .init(style: "glass", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#1C1C1E")
            )
        )

        let resolved = AppModel.resolvedThemeOverrides(
            globalMods: [globalMod],
            projectMods: [],
            selectedGlobalPath: "/global/dual-theme",
            selectedProjectPath: nil
        )

        XCTAssertEqual(resolved.dark.palette?.backgroundHex, "#000000")
        XCTAssertEqual(resolved.dark.palette?.panelHex, "#121212")
        XCTAssertEqual(resolved.dark.bubbles?.style, "glass")
        XCTAssertEqual(resolved.dark.bubbles?.assistantBackgroundHex, "#1C1C1E")
        XCTAssertEqual(resolved.dark.typography?.titleSize, 21)
    }

    func testModEditSafetyAbsolutePathResolvesRelativePathsWithinProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = ModEditSafety.absolutePath(for: "mods/LocalMod/ui.mod.json", projectPath: root.path)
        let expected = root
            .appendingPathComponent("mods/LocalMod/ui.mod.json")
            .standardizedFileURL
            .path
        XCTAssertEqual(resolved, expected)
    }

    func testModEditSafetyIsWithinDoesNotMatchSiblingRoots() {
        XCTAssertTrue(ModEditSafety.isWithin(rootPath: "/tmp/mods", path: "/tmp/mods/file.txt"))
        XCTAssertFalse(ModEditSafety.isWithin(rootPath: "/tmp/mods", path: "/tmp/mods2/file.txt"))
        XCTAssertTrue(ModEditSafety.isWithin(rootPath: "/tmp/mods/", path: "/tmp/mods/file.txt"))
    }

    func testModEditSafetyFilterModChangesSelectsGlobalAndProjectModFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let globalRoot = root.appendingPathComponent("globalMods", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let projectMods = projectRoot.appendingPathComponent("mods", isDirectory: true)

        try FileManager.default.createDirectory(at: globalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectMods, withIntermediateDirectories: true)

        let changes: [RuntimeFileChange] = [
            RuntimeFileChange(path: "mods/LocalMod/ui.mod.json", kind: "modify", diff: "{}"),
            RuntimeFileChange(
                path: globalRoot.appendingPathComponent("GlobalMod/ui.mod.json").path,
                kind: "modify",
                diff: "{}"
            ),
            RuntimeFileChange(path: "README.md", kind: "modify", diff: "{}"),
        ]

        let filtered = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: projectRoot.path,
            globalRootPath: globalRoot.path,
            projectRootPath: projectMods.path
        )

        XCTAssertEqual(Set(filtered.map(\.path)), Set([changes[0].path, changes[1].path]))
    }

    func testModEditSafetyFilterModChangesRejectsTraversalOutsideProjectMods() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-traversal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let projectMods = projectRoot.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let changes: [RuntimeFileChange] = [
            RuntimeFileChange(path: "../mods/evil.json", kind: "modify", diff: "{}"),
        ]

        let filtered = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: projectRoot.path,
            globalRootPath: nil,
            projectRootPath: projectMods.path
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testModEditSafetySnapshotCaptureAndRestoreRestoresOriginalContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let globalRoot = root.appendingPathComponent("globalMods", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let projectMods = projectRoot.appendingPathComponent("mods", isDirectory: true)
        let snapshotsRoot = root.appendingPathComponent("snapshots", isDirectory: true)

        try FileManager.default.createDirectory(at: globalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectMods, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotsRoot, withIntermediateDirectories: true)

        let globalFile = globalRoot.appendingPathComponent("GlobalMod/ui.mod.json")
        try FileManager.default.createDirectory(at: globalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "global-v1".write(to: globalFile, atomically: true, encoding: .utf8)

        let projectFile = projectMods.appendingPathComponent("LocalMod/ui.mod.json")
        try FileManager.default.createDirectory(at: projectFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "project-v1".write(to: projectFile, atomically: true, encoding: .utf8)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let threadID = UUID()
        let snapshot = try ModEditSafety.captureSnapshot(
            snapshotsRootURL: snapshotsRoot,
            globalRootPath: globalRoot.path,
            projectRootPath: projectMods.path,
            threadID: threadID,
            startedAt: startedAt
        )

        try "global-v2".write(to: globalFile, atomically: true, encoding: .utf8)
        try "project-v2".write(to: projectFile, atomically: true, encoding: .utf8)

        try ModEditSafety.restore(from: snapshot)

        XCTAssertEqual(try String(contentsOf: globalFile, encoding: .utf8), "global-v1")
        XCTAssertEqual(try String(contentsOf: projectFile, encoding: .utf8), "project-v1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.rootURL.path))
    }

    @MainActor
    func testArchivingSelectedThreadReselectsFallbackThread() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-archive-select-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Archive Select",
            path: root.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let first = try await repositories.threadRepository.createThread(projectID: project.id, title: "First")
        let second = try await repositories.threadRepository.createThread(projectID: project.id, title: "Second")

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await model.refreshProjects()
        model.selectedProjectID = project.id
        try await model.refreshThreads()
        model.selectedThreadID = first.id
        try await model.persistSelection()

        model.archiveThread(threadID: first.id)

        try await waitUntil {
            model.selectedThreadID == second.id
                && model.archivedThreads.contains(where: { $0.id == first.id })
        }
    }

    @MainActor
    func testArchiveRemovesMemoryInfluenceAndUnarchiveRestoresIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-archive-memory-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Archive Memory",
            path: root.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(projectID: project.id, title: "Memory Thread")

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await model.refreshProjects()
        model.selectedProjectID = project.id
        try await model.refreshThreads()
        try await model.refreshArchivedThreads()

        let store = ProjectMemoryStore(projectPath: project.path)
        try await store.ensureStructure()
        try await store.write(
            .summaryLog,
            text: """
            # Summary Log
            ## 2026-02-18 12:00:00
            - Thread: `\(thread.id.uuidString)`
            - User: keep this memory
            - Assistant: remembered phrase for archive test
            """
        )
        let before = try await store.keywordSearch(query: "remembered phrase")
        XCTAssertFalse(before.isEmpty)

        model.archiveThread(threadID: thread.id)
        try await waitUntil {
            model.archivedThreads.contains(where: { $0.id == thread.id })
        }

        let hidden = try await store.keywordSearch(query: "remembered phrase")
        XCTAssertTrue(hidden.isEmpty)

        model.unarchiveThread(threadID: thread.id)
        try await waitUntil {
            !model.archivedThreads.contains(where: { $0.id == thread.id })
        }

        let restored = try await store.keywordSearch(query: "remembered phrase")
        XCTAssertFalse(restored.isEmpty)
    }

    @MainActor
    func testCreateGlobalNewChatStartsDraftInGeneralProjectWithoutPersistingThread() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-global-chat-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Work Project",
            path: root.path,
            trustState: .trusted,
            isGeneralProject: false
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await model.refreshProjects()
        try await model.ensureGeneralProject()
        try await model.refreshProjects()
        model.selectedProjectID = project.id
        try await model.refreshGeneralThreads()

        let generalID = try XCTUnwrap(model.generalProject?.id)
        let baseline = model.generalThreads.count
        model.createGlobalNewChat()

        try await waitUntil {
            model.selectedProjectID == generalID
                && model.generalThreads.count == baseline
                && model.selectedThreadID == nil
                && model.draftChatProjectID == generalID
                && model.detailDestination == .thread
        }
    }

    @MainActor
    func testLoadInitialDataEntersOnboardingWhenRuntimeIsUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-onboarding-startup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()
        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil, storagePaths: paths)

        await model.loadInitialData()

        XCTAssertTrue(model.isOnboardingActive)
        XCTAssertEqual(model.detailDestination, .none)
    }

    @MainActor
    func testCompleteOnboardingActivatesGeneralDraftWithoutPersistingThread() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-onboarding-complete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()
        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil, storagePaths: paths)

        model.onboardingMode = .active
        model.runtimeStatus = .connected
        model.runtimeIssue = nil
        model.accountState = RuntimeAccountState(account: nil, authMode: .unknown, requiresOpenAIAuth: false)

        model.completeOnboardingIfReady()

        try await waitUntil {
            !model.isOnboardingActive
                && model.generalProject != nil
                && model.selectedProjectID == model.generalProject?.id
                && model.draftChatProjectID == model.generalProject?.id
                && model.selectedThreadID == nil
                && model.detailDestination == .thread
        }

        let generalID = try XCTUnwrap(model.generalProject?.id)
        let persistedGeneralThreads = try await repositories.threadRepository.listThreads(projectID: generalID)
        XCTAssertTrue(persistedGeneralThreads.isEmpty)
    }

    @MainActor
    func testEnterOnboardingFromSignedOutResetsThreadSelection() {
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil
        )

        model.onboardingMode = .inactive
        model.selectedProjectID = UUID()
        model.selectedThreadID = UUID()
        model.draftChatProjectID = UUID()
        model.detailDestination = .thread

        model.enterOnboarding(reason: .signedOut)

        XCTAssertTrue(model.isOnboardingActive)
        XCTAssertNil(model.selectedThreadID)
        XCTAssertNil(model.draftChatProjectID)
        XCTAssertEqual(model.detailDestination, .none)
    }

    @MainActor
    func testRuntimeTerminationDoesNotForceOnboardingWhenInactive() {
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil
        )

        model.onboardingMode = .inactive
        model.runtimeStatus = .connected
        model.runtimeIssue = nil

        model.handleRuntimeTermination(detail: "Simulated runtime stop")

        XCTAssertFalse(model.isOnboardingActive)
    }

    @MainActor
    func testSelectingGeneralThreadSwitchesSelectedProjectAndPersistsSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-general-thread-selection-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Work Project",
            path: root.path,
            trustState: .trusted,
            isGeneralProject: false
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await model.refreshProjects()
        try await model.ensureGeneralProject()
        try await model.refreshProjects()

        let generalID = try XCTUnwrap(model.generalProject?.id)
        let generalThread = try await repositories.threadRepository.createThread(
            projectID: generalID,
            title: "General existing thread"
        )
        try await model.refreshGeneralThreads(generalProjectID: generalID)

        model.selectedProjectID = project.id
        try await model.refreshThreads()

        model.selectThread(generalThread.id)

        try await waitUntil(timeout: 8.0) {
            model.selectedProjectID == generalID
                && model.selectedThreadID == generalThread.id
        }

        let persistedProjectID = try await repositories.preferenceRepository.getPreference(key: .lastOpenedProjectID)
        let persistedThreadID = try await repositories.preferenceRepository.getPreference(key: .lastOpenedThreadID)
        XCTAssertEqual(persistedProjectID, generalID.uuidString)
        XCTAssertEqual(persistedThreadID, generalThread.id.uuidString)
        XCTAssertFalse(model.isProjectSidebarVisuallySelected(project.id))
    }

    func testAutoTitleFromFirstTurnPrefersAssistantAndCleansPreamble() {
        let title = AppModel.autoTitleFromFirstTurn(
            userText: "Need help with CI.",
            assistantText: "Sure, set up CI workflow for iOS builds and tests."
        )

        XCTAssertEqual(title, "Set up CI workflow for iOS builds and tests")
    }

    func testAutoTitleFromFirstTurnFallsBackToUserTextWhenAssistantIsEmpty() {
        let title = AppModel.autoTitleFromFirstTurn(
            userText: "Fix flaky sidebar hover in dark mode",
            assistantText: "   "
        )

        XCTAssertEqual(title, "Fix flaky sidebar hover in dark mode")
    }

    func testStoragePathsUniqueProjectDirectoryAddsNumericSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-storage-suffix-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()
        let first = paths.uniqueProjectDirectoryURL(requestedName: "My App")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)

        let second = paths.uniqueProjectDirectoryURL(requestedName: "My App")
        XCTAssertEqual(first.lastPathComponent, "My-App")
        XCTAssertEqual(second.lastPathComponent, "My-App-2")
    }

    @MainActor
    func testEnsureGeneralProjectUsesConfiguredStorageRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-storage-general-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()

        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil, storagePaths: paths)

        try await model.refreshProjects()
        try await model.ensureGeneralProject()
        try await model.refreshProjects()

        XCTAssertEqual(model.generalProject?.path, paths.generalProjectURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.generalProjectURL.path))
    }

    @MainActor
    func testInitializeGitForSelectedProjectCreatesGitDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-git-init-\(UUID().uuidString)", isDirectory: true)
        let projectURL = root.appendingPathComponent("project", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let database = try MetadataDatabase(databaseURL: root.appendingPathComponent("metadata.sqlite"))
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Project",
            path: projectURL.path,
            trustState: .untrusted,
            isGeneralProject: false
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await model.refreshProjects()
        model.selectedProjectID = project.id

        model.initializeGitForSelectedProject()

        try await waitUntil {
            FileManager.default.fileExists(atPath: projectURL.appendingPathComponent(".git").path)
        }
    }

    @MainActor
    func testRewriteMetadataForManagedRootChangeRewritesProjectModAndSkillPaths() async throws {
        let oldRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-root-old-\(UUID().uuidString)", isDirectory: true)
        let newRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-root-new-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }

        let oldPaths = CodexChatStoragePaths(rootURL: oldRoot)
        let newPaths = CodexChatStoragePaths(rootURL: newRoot)
        try oldPaths.ensureRootStructure()
        try newPaths.ensureRootStructure()

        let database = try MetadataDatabase(databaseURL: oldPaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)

        let projectPath = oldPaths.projectsURL.appendingPathComponent("Workspace", isDirectory: true).path
        let project = try await repositories.projectRepository.createProject(
            named: "Workspace",
            path: projectPath,
            trustState: .trusted,
            isGeneralProject: false
        )
        _ = try await repositories.projectRepository.updateProjectUIModPath(
            id: project.id,
            uiModPath: oldPaths.projectsURL.appendingPathComponent("Workspace/mods/theme", isDirectory: true).path
        )
        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            projectID: project.id,
            skillPath: oldPaths.projectsURL.appendingPathComponent("Workspace/.agents/skills/my-skill", isDirectory: true).path,
            enabled: true
        )
        try await repositories.preferenceRepository.setPreference(
            key: .globalUIModPath,
            value: oldPaths.globalModsURL.appendingPathComponent("global-theme", isDirectory: true).path
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil, storagePaths: oldPaths)
        try await model.refreshProjects()
        try await model.rewriteMetadataForManagedRootChange(oldPaths: oldPaths, newPaths: newPaths)

        let rewritten = try await repositories.projectRepository.getProject(id: project.id)
        XCTAssertEqual(rewritten?.path, newPaths.projectsURL.appendingPathComponent("Workspace", isDirectory: true).path)
        XCTAssertEqual(
            rewritten?.uiModPath,
            newPaths.projectsURL.appendingPathComponent("Workspace/mods/theme", isDirectory: true).path
        )

        let enabledPaths = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(projectID: project.id)
        XCTAssertTrue(enabledPaths.contains(newPaths.projectsURL.appendingPathComponent("Workspace/.agents/skills/my-skill", isDirectory: true).path))
        XCTAssertFalse(enabledPaths.contains(oldPaths.projectsURL.appendingPathComponent("Workspace/.agents/skills/my-skill", isDirectory: true).path))

        let globalModPath = try await repositories.preferenceRepository.getPreference(key: .globalUIModPath)
        XCTAssertEqual(globalModPath, newPaths.globalModsURL.appendingPathComponent("global-theme", isDirectory: true).path)
    }

    @MainActor
    func testMigrateStorageRootDoesNotDeleteOldRootUntilRestartStep() async throws {
        let defaults = UserDefaults.standard
        let priorRoot = defaults.string(forKey: CodexChatStoragePaths.rootPreferenceKey)
        defer {
            if let priorRoot {
                defaults.set(priorRoot, forKey: CodexChatStoragePaths.rootPreferenceKey)
            } else {
                defaults.removeObject(forKey: CodexChatStoragePaths.rootPreferenceKey)
            }
        }

        let oldRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-migrate-old-\(UUID().uuidString)", isDirectory: true)
        let newRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-migrate-new-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }

        let oldPaths = CodexChatStoragePaths(rootURL: oldRoot)
        try oldPaths.ensureRootStructure()
        let sentinel = oldRoot.appendingPathComponent("sentinel.txt", isDirectory: false)
        try "still here".write(to: sentinel, atomically: true, encoding: .utf8)

        let database = try MetadataDatabase(databaseURL: oldPaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        _ = try await repositories.projectRepository.createProject(
            named: "Project",
            path: oldPaths.projectsURL.appendingPathComponent("Project", isDirectory: true).path,
            trustState: .trusted,
            isGeneralProject: false
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil, storagePaths: oldPaths)
        try await model.refreshProjects()

        let result = try await model.migrateStorageRoot(to: newRoot)

        XCTAssertEqual(result.oldPaths.rootURL.path, oldRoot.path)
        XCTAssertEqual(result.newPaths.rootURL.path, newRoot.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.newPaths.metadataDatabaseURL.path))
    }

    func testShellSplitTreeSupportsRecursiveSplitAndCloseCollapse() {
        let pane1 = ShellPaneState(id: UUID(), cwd: "/tmp/one")
        let pane2 = ShellPaneState(id: UUID(), cwd: "/tmp/two")
        let pane3 = ShellPaneState(id: UUID(), cwd: "/tmp/three")

        var root: ShellSplitNode = .leaf(pane1)
        XCTAssertTrue(ShellSplitTree.splitLeaf(in: &root, paneID: pane1.id, axis: .horizontal, newPane: pane2))
        XCTAssertTrue(ShellSplitTree.splitLeaf(in: &root, paneID: pane2.id, axis: .vertical, newPane: pane3))
        XCTAssertEqual(root.leafCount(), 3)
        XCTAssertEqual(ShellSplitTree.findLeaf(in: root, paneID: pane3.id)?.cwd, "/tmp/three")

        let closePane2 = ShellSplitTree.closeLeaf(in: root, paneID: pane2.id)
        XCTAssertTrue(closePane2.didClose)
        guard let afterClosePane2 = closePane2.root else {
            XCTFail("Expected non-empty tree after closing pane2")
            return
        }
        XCTAssertEqual(afterClosePane2.leafCount(), 2)
        XCTAssertNotNil(ShellSplitTree.findLeaf(in: afterClosePane2, paneID: pane3.id))

        let closePane1 = ShellSplitTree.closeLeaf(in: afterClosePane2, paneID: pane1.id)
        XCTAssertTrue(closePane1.didClose)
        guard let afterClosePane1 = closePane1.root else {
            XCTFail("Expected one-pane tree after closing pane1")
            return
        }
        XCTAssertEqual(afterClosePane1.leafCount(), 1)
        XCTAssertNotNil(ShellSplitTree.findLeaf(in: afterClosePane1, paneID: pane3.id))

        let closePane3 = ShellSplitTree.closeLeaf(in: afterClosePane1, paneID: pane3.id)
        XCTAssertTrue(closePane3.didClose)
        XCTAssertNil(closePane3.root)
    }

    @MainActor
    func testShellWorkspaceIsScopedPerProjectAndNotRestoredInNewModel() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project1 = ProjectRecord(name: "P1", path: "/tmp/p1", trustState: .trusted)
        let project2 = ProjectRecord(name: "P2", path: "/tmp/p2", trustState: .trusted)
        model.projectsState = .loaded([project1, project2])

        model.selectedProjectID = project1.id
        model.createShellSession()
        XCTAssertEqual(model.shellWorkspacesByProjectID[project1.id]?.sessions.count, 1)

        model.selectedProjectID = project2.id
        model.createShellSession()
        XCTAssertEqual(model.shellWorkspacesByProjectID[project2.id]?.sessions.count, 1)
        XCTAssertEqual(model.shellWorkspacesByProjectID[project1.id]?.sessions.count, 1)

        let secondModel = AppModel(repositories: nil, runtime: nil, bootError: nil)
        XCTAssertTrue(secondModel.shellWorkspacesByProjectID.isEmpty)
    }

    @MainActor
    func testSplitShellPaneInheritsCurrentPaneDirectory() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project = ProjectRecord(name: "P1", path: "/tmp/project-root", trustState: .trusted)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id
        model.createShellSession()

        guard var session = model.selectedShellSession else {
            XCTFail("Missing selected shell session")
            return
        }
        let sourcePaneID = session.activePaneID
        XCTAssertEqual(
            ShellSplitTree.findLeaf(in: session.rootNode, paneID: sourcePaneID)?.cwd,
            "/tmp/project-root"
        )

        model.splitShellPane(sessionID: session.id, paneID: sourcePaneID, axis: .horizontal)
        guard let updatedWorkspace = model.shellWorkspacesByProjectID[project.id],
              let updatedSession = updatedWorkspace.selectedSession()
        else {
            XCTFail("Missing updated shell workspace")
            return
        }
        session = updatedSession
        XCTAssertEqual(session.rootNode.leafCount(), 2)

        guard let activePane = ShellSplitTree.findLeaf(in: session.rootNode, paneID: session.activePaneID) else {
            XCTFail("Missing active pane after split")
            return
        }
        XCTAssertEqual(activePane.cwd, "/tmp/project-root")
    }

    @MainActor
    func testClosingLastPaneAutoClosesSession() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project = ProjectRecord(name: "P1", path: "/tmp/project-root", trustState: .trusted)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id
        model.createShellSession()

        guard let session = model.selectedShellSession else {
            XCTFail("Missing selected shell session")
            return
        }

        model.closeShellPane(sessionID: session.id, paneID: session.activePaneID)
        let workspace = model.shellWorkspacesByProjectID[project.id]
        XCTAssertEqual(workspace?.sessions.count, 0)
        XCTAssertNil(workspace?.selectedSessionID)
    }

    @MainActor
    func testTogglingShellWorkspaceAutoCreatesInitialSession() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project = ProjectRecord(name: "P1", path: "/tmp/project-root", trustState: .trusted)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        model.toggleShellWorkspace()
        try await waitUntil {
            model.isShellWorkspaceVisible
        }

        guard let workspace = model.shellWorkspacesByProjectID[project.id],
              let session = workspace.selectedSession()
        else {
            XCTFail("Missing shell workspace after opening drawer")
            return
        }
        XCTAssertEqual(workspace.sessions.count, 1)
        XCTAssertEqual(
            ShellSplitTree.findLeaf(in: session.rootNode, paneID: session.activePaneID)?.cwd,
            project.path
        )

        model.toggleShellWorkspace()
        XCTAssertFalse(model.isShellWorkspaceVisible)

        model.toggleShellWorkspace()
        try await waitUntil {
            model.isShellWorkspaceVisible
        }
        XCTAssertEqual(model.shellWorkspacesByProjectID[project.id]?.sessions.count, 1)
    }

    @MainActor
    func testTogglingShellWorkspaceWithoutProjectShowsStatusMessage() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.projectsState = .loaded([])
        model.selectedProjectID = nil

        model.toggleShellWorkspace()
        try await waitUntil {
            model.projectStatusMessage == "Select a project to open Shell Workspace."
        }

        XCTAssertFalse(model.isShellWorkspaceVisible)
        XCTAssertTrue(model.shellWorkspacesByProjectID.isEmpty)
    }

    @MainActor
    func testDismissingUntrustedShellWarningKeepsWorkspaceClosed() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project = ProjectRecord(name: "Untrusted", path: "/tmp/untrusted", trustState: .untrusted)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        model.toggleShellWorkspace()
        try await waitUntil {
            model.activeUntrustedShellWarning?.projectID == project.id
        }

        model.dismissUntrustedShellWarning()

        XCTAssertNil(model.activeUntrustedShellWarning)
        XCTAssertFalse(model.isShellWorkspaceVisible)
        XCTAssertNil(model.shellWorkspacesByProjectID[project.id])
    }

    @MainActor
    func testTogglingShellWorkspaceReselectsSessionWhenSelectionMissing() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project = ProjectRecord(name: "P1", path: "/tmp/project-root", trustState: .trusted)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        model.createShellSession()
        model.createShellSession()

        var workspace = try XCTUnwrap(model.shellWorkspacesByProjectID[project.id])
        let fallbackSessionID = try XCTUnwrap(workspace.sessions.first?.id)
        workspace.selectedSessionID = nil
        model.shellWorkspacesByProjectID[project.id] = workspace

        model.isShellWorkspaceVisible = false
        model.toggleShellWorkspace()
        try await waitUntil {
            model.isShellWorkspaceVisible
        }

        let updatedWorkspace = try XCTUnwrap(model.shellWorkspacesByProjectID[project.id])
        XCTAssertEqual(updatedWorkspace.sessions.count, 2)
        XCTAssertEqual(updatedWorkspace.selectedSessionID, fallbackSessionID)
    }

    @MainActor
    func testUntrustedShellWarningAppearsOncePerProject() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let project = ProjectRecord(name: "Untrusted", path: "/tmp/untrusted", trustState: .untrusted)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        model.toggleShellWorkspace()
        try await waitUntil {
            model.activeUntrustedShellWarning?.projectID == project.id
        }
        XCTAssertFalse(model.isShellWorkspaceVisible)

        model.confirmUntrustedShellWarning()
        try await waitUntil {
            model.isShellWorkspaceVisible
        }
        XCTAssertNil(model.activeUntrustedShellWarning)
        XCTAssertEqual(model.shellWorkspacesByProjectID[project.id]?.sessions.count, 1)

        model.isShellWorkspaceVisible = false
        model.toggleShellWorkspace()
        try await waitUntil {
            model.isShellWorkspaceVisible
        }
        XCTAssertNil(model.activeUntrustedShellWarning)
        XCTAssertEqual(model.shellWorkspacesByProjectID[project.id]?.sessions.count, 1)
    }

    func testUntrustedShellAcknowledgementsCodecRoundTrips() {
        let values: Set<UUID> = [UUID(), UUID()]
        let encoded = UntrustedShellAcknowledgementsCodec.encode(values)
        let decoded = UntrustedShellAcknowledgementsCodec.decode(encoded)
        XCTAssertEqual(decoded, values)
    }

    private func makeApprovalRequest(id: Int) -> RuntimeApprovalRequest {
        RuntimeApprovalRequest(
            id: id,
            kind: .commandExecution,
            method: "item/commandExecution/requestApproval",
            threadID: "thr_1",
            turnID: "turn_1",
            itemID: "item_\(id)",
            reason: "test",
            risk: nil,
            cwd: "/tmp",
            command: ["echo", "hello"],
            changes: [],
            detail: "{}"
        )
    }

    private func makeMod(
        scope: ModScope = .global,
        path: String,
        theme: ModThemeOverride,
        darkTheme: ModThemeOverride? = nil
    ) -> DiscoveredUIMod {
        let manifest = UIModManifest(
            id: path.replacingOccurrences(of: "/", with: "-"),
            name: "TestMod-\(path)",
            version: "1.0.0"
        )
        let definition = UIModDefinition(
            schemaVersion: 1,
            manifest: manifest,
            theme: theme,
            darkTheme: darkTheme
        )
        return DiscoveredUIMod(
            scope: scope,
            directoryPath: path,
            definitionPath: "\(path)/ui.mod.json",
            definition: definition,
            computedChecksum: nil
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 3.0,
        pollInterval: UInt64 = 50_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        XCTFail("Condition not satisfied before timeout.")
    }
}
