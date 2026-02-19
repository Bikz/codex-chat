import CodexChatInfra
@testable import CodexChatShared
import Foundation
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

    func testEnsureGeneralDraftChatSelectionIfNeededPrefersSelectedProject() async throws {
        let context = try makeModelContext(prefix: "selected-project-draft")
        defer { try? FileManager.default.removeItem(at: context.rootURL) }

        let generalURL = context.rootURL.appendingPathComponent("general", isDirectory: true)
        let projectURL = context.rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: generalURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        _ = try await context.repositories.projectRepository.createProject(
            named: "General",
            path: generalURL.path,
            trustState: .trusted,
            isGeneralProject: true
        )
        let selectedProject = try await context.repositories.projectRepository.createProject(
            named: "Workspace",
            path: projectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )

        try await context.model.refreshProjects()
        context.model.selectedProjectID = selectedProject.id
        context.model.selectedThreadID = nil
        context.model.draftChatProjectID = nil
        context.model.refreshConversationState()

        context.model.ensureGeneralDraftChatSelectionIfNeeded()

        XCTAssertEqual(context.model.selectedProjectID, selectedProject.id)
        XCTAssertNil(context.model.selectedThreadID)
        XCTAssertEqual(context.model.draftChatProjectID, selectedProject.id)
        XCTAssertTrue(context.model.hasActiveDraftChatForSelectedProject)
    }

    func testSelectProjectArmsDraftWhenProjectHasNoThreads() async throws {
        let context = try makeModelContext(prefix: "select-project-draft")
        defer { try? FileManager.default.removeItem(at: context.rootURL) }

        let generalURL = context.rootURL.appendingPathComponent("general", isDirectory: true)
        let projectURL = context.rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: generalURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        _ = try await context.repositories.projectRepository.createProject(
            named: "General",
            path: generalURL.path,
            trustState: .trusted,
            isGeneralProject: true
        )
        let selectedProject = try await context.repositories.projectRepository.createProject(
            named: "Workspace",
            path: projectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )

        try await context.model.refreshProjects()
        context.model.selectedProjectID = nil
        context.model.selectedThreadID = nil
        context.model.draftChatProjectID = nil
        context.model.refreshConversationState()

        context.model.selectProject(selectedProject.id)

        try await waitUntil {
            context.model.selectedProjectID == selectedProject.id
                && context.model.selectedThreadID == nil
                && context.model.draftChatProjectID == selectedProject.id
                && context.model.hasActiveDraftChatForSelectedProject
        }
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

    private func waitUntil(
        timeout: TimeInterval = 5.0,
        pollInterval: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = Date()
        while true {
            if condition() {
                return
            }
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Condition not met within timeout")
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }
}
