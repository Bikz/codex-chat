import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import XCTest

@MainActor
final class ThreadComposerOverrideTests: XCTestCase {
    func testSettingsNavigationTargetProjectsSectionRoundTrip() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()

        model.requestSettingsNavigationToProjects(projectID: projectID)

        let target = model.consumeSettingsNavigationTarget()
        XCTAssertEqual(target?.section, .projects)
        XCTAssertEqual(target?.projectID, projectID)
        XCTAssertNil(model.consumeSettingsNavigationTarget())
    }

    func testThreadOverridesSwitchWithThreadSelection() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadA = UUID()
        let threadB = UUID()

        model.projectsState = .loaded([makeProject(id: projectID)])
        model.selectedProjectID = projectID

        model.selectedThreadID = threadA
        model.setComposerWebSearchOverrideForCurrentContext(.live)
        model.setComposerMemoryModeOverrideForCurrentContext(.off)

        model.selectedThreadID = threadB
        model.setComposerMemoryModeOverrideForCurrentContext(.summariesOnly)

        model.selectedThreadID = threadA
        XCTAssertEqual(model.composerMemoryMode, .off)
        XCTAssertEqual(model.composerWebSearchModeForCurrentContext, .live)

        model.selectedThreadID = threadB
        XCTAssertEqual(model.composerMemoryMode, .summariesOnly)
        XCTAssertEqual(model.composerWebSearchModeForCurrentContext, .cached)
    }

    func testClearOverridesReturnsToInheritedSettings() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadID = UUID()
        let project = makeProject(id: projectID)

        model.projectsState = .loaded([project])
        model.selectedProjectID = projectID
        model.selectedThreadID = threadID

        model.setComposerWebSearchOverrideForCurrentContext(.live)
        model.setComposerMemoryModeOverrideForCurrentContext(.off)
        model.setComposerSafetyOverrideForCurrentContext(
            sandboxMode: .workspaceWrite,
            approvalPolicy: .onRequest,
            networkAccess: true
        )
        XCTAssertTrue(model.hasComposerOverrideForCurrentContext)

        model.clearComposerOverridesForCurrentContext()

        XCTAssertFalse(model.hasComposerOverrideForCurrentContext)
        XCTAssertEqual(model.composerMemoryMode, .projectDefault)
        XCTAssertEqual(model.composerWebSearchModeForCurrentContext, project.webSearch)
        XCTAssertEqual(model.composerSafetySettingsForCurrentContext.sandboxMode, project.sandboxMode)
        XCTAssertEqual(model.composerSafetySettingsForCurrentContext.approvalPolicy, project.approvalPolicy)
    }

    func testDraftOverrideMaterializesIntoThreadOverride() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadID = UUID()

        model.projectsState = .loaded([makeProject(id: projectID)])
        model.beginDraftChat(in: projectID)
        model.setComposerWebSearchOverrideForCurrentContext(.live)
        model.setComposerMemoryModeOverrideForCurrentContext(.summariesOnly)

        model.materializeDraftComposerOverrideIfNeeded(into: threadID)

        XCTAssertNil(model.draftComposerOverride)
        XCTAssertEqual(model.threadComposerOverridesByThreadID[threadID]?.webSearchOverride, .live)
        XCTAssertEqual(model.threadComposerOverridesByThreadID[threadID]?.memoryModeOverride, .summariesOnly)
    }

    func testThreadOverrideResolutionWinsForSafetyWebAndMemory() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let project = makeProject(id: UUID())
        let overrideSafety = ProjectSafetySettings(
            sandboxMode: .workspaceWrite,
            approvalPolicy: .never,
            networkAccess: true,
            webSearch: .disabled
        )

        model.threadComposerOverridesByThreadID[threadID] = AppModel.ThreadComposerOverride(
            webSearchOverride: .live,
            memoryModeOverride: .off,
            safetyOverride: overrideSafety
        )

        XCTAssertEqual(model.effectiveWebSearchMode(for: threadID, project: project), .live)
        XCTAssertEqual(model.effectiveComposerMemoryWriteMode(for: project, threadID: threadID), .off)
        XCTAssertEqual(model.effectiveSafetySettings(for: threadID, project: project), overrideSafety)

        XCTAssertEqual(model.effectiveWebSearchMode(for: nil, project: project), project.webSearch)
        XCTAssertEqual(
            model.effectiveComposerMemoryWriteMode(for: project, threadID: nil),
            project.memoryWriteMode
        )
        XCTAssertEqual(model.effectiveSafetySettings(for: nil, project: project).approvalPolicy, project.approvalPolicy)
    }

    func testPersistAndRestoreThreadComposerOverridesRoundTrip() async throws {
        let rootURL = try makeTempDirectory(prefix: "thread-composer-override-persist")
        let databaseURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        let database = try MetadataDatabase(databaseURL: databaseURL)
        let repositories = MetadataRepositories(database: database)

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        let threadID = UUID()
        let persisted = AppModel.ThreadComposerOverride(
            webSearchOverride: .live,
            memoryModeOverride: .summariesAndKeyFacts,
            safetyOverride: ProjectSafetySettings(
                sandboxMode: .workspaceWrite,
                approvalPolicy: .onRequest,
                networkAccess: true,
                webSearch: .live
            )
        )
        model.threadComposerOverridesByThreadID = [threadID: persisted]
        try await model.persistThreadComposerOverridesPreference()

        let restoredModel = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await restoredModel.restoreThreadComposerOverridesIfNeeded()

        XCTAssertEqual(restoredModel.threadComposerOverridesByThreadID[threadID], persisted)
    }

    private func makeProject(id: UUID) -> ProjectRecord {
        ProjectRecord(
            id: id,
            name: "Workspace",
            path: "/tmp/workspace",
            trustState: .trusted,
            sandboxMode: .readOnly,
            approvalPolicy: .untrusted,
            networkAccess: false,
            webSearch: .cached,
            memoryWriteMode: .summariesOnly,
            memoryEmbeddingsEnabled: false
        )
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
