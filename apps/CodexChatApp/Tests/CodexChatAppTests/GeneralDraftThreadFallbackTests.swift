import CodexChatInfra
@testable import CodexChatShared
import XCTest

@MainActor
final class GeneralDraftThreadFallbackTests: XCTestCase {
    func testEnsureGeneralDraftChatSelectionIfNeededStartsGeneralDraftWhenNoThreadSelected() async throws {
        let context = try makeModelContext(prefix: "general-draft-fallback")
        defer { try? FileManager.default.removeItem(at: context.rootURL) }

        let generalURL = context.rootURL.appendingPathComponent("general", isDirectory: true)
        try FileManager.default.createDirectory(at: generalURL, withIntermediateDirectories: true)
        let generalProject = try await context.repositories.projectRepository.createProject(
            named: "General",
            path: generalURL.path,
            trustState: .trusted,
            isGeneralProject: true
        )

        try await context.model.refreshProjects()
        context.model.selectedProjectID = nil
        context.model.selectedThreadID = nil
        context.model.draftChatProjectID = nil
        context.model.refreshConversationState()

        context.model.ensureGeneralDraftChatSelectionIfNeeded()

        XCTAssertEqual(context.model.selectedProjectID, generalProject.id)
        XCTAssertNil(context.model.selectedThreadID)
        XCTAssertEqual(context.model.draftChatProjectID, generalProject.id)
        XCTAssertTrue(context.model.hasActiveDraftChatForSelectedProject)

        guard case let .loaded(entries) = context.model.conversationState else {
            XCTFail("Expected an empty draft conversation state.")
            return
        }
        XCTAssertTrue(entries.isEmpty)
    }

    func testEnsureGeneralDraftChatSelectionIfNeededNoOpsWhenThreadAlreadySelected() async throws {
        let context = try makeModelContext(prefix: "general-draft-noop")
        defer { try? FileManager.default.removeItem(at: context.rootURL) }

        let generalURL = context.rootURL.appendingPathComponent("general", isDirectory: true)
        try FileManager.default.createDirectory(at: generalURL, withIntermediateDirectories: true)
        let generalProject = try await context.repositories.projectRepository.createProject(
            named: "General",
            path: generalURL.path,
            trustState: .trusted,
            isGeneralProject: true
        )
        let selectedThread = try await context.repositories.threadRepository.createThread(
            projectID: generalProject.id,
            title: "Existing"
        )

        try await context.model.refreshProjects()
        context.model.selectedProjectID = generalProject.id
        context.model.selectedThreadID = selectedThread.id
        context.model.draftChatProjectID = nil
        context.model.refreshConversationState()

        context.model.ensureGeneralDraftChatSelectionIfNeeded()

        XCTAssertEqual(context.model.selectedProjectID, generalProject.id)
        XCTAssertEqual(context.model.selectedThreadID, selectedThread.id)
        XCTAssertNil(context.model.draftChatProjectID)
    }

    private func makeModelContext(prefix: String) throws -> ModelContext {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let dbURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        return ModelContext(rootURL: rootURL, model: model, repositories: repositories)
    }

    private struct ModelContext {
        let rootURL: URL
        let model: AppModel
        let repositories: MetadataRepositories
    }
}
