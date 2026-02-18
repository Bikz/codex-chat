import CodexChatCore
import Foundation
import GRDB
@testable import CodexChatInfra
import XCTest

final class CodexChatInfraTests: XCTestCase {
    func testMigrationCreatesExpectedTables() throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let tableNames = try database.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tableNames.contains("projects"))
        XCTAssertTrue(tableNames.contains("threads"))
        XCTAssertTrue(tableNames.contains("preferences"))
    }

    func testProjectThreadAndPreferencePersistence() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(named: "Inbox")
        XCTAssertEqual(project.name, "Inbox")

        let thread = try await repositories.threadRepository.createThread(projectID: project.id, title: "First")
        XCTAssertEqual(thread.projectId, project.id)

        let listedProjects = try await repositories.projectRepository.listProjects()
        XCTAssertEqual(listedProjects.count, 1)
        XCTAssertEqual(listedProjects.first?.id, project.id)

        let listedThreads = try await repositories.threadRepository.listThreads(projectID: project.id)
        XCTAssertEqual(listedThreads.count, 1)
        XCTAssertEqual(listedThreads.first?.id, thread.id)

        try await repositories.preferenceRepository.setPreference(
            key: .lastOpenedProjectID,
            value: project.id.uuidString
        )

        let persistedProjectPreference = try await repositories.preferenceRepository.getPreference(key: .lastOpenedProjectID)
        XCTAssertEqual(persistedProjectPreference, project.id.uuidString)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-test-\(UUID().uuidString).sqlite")
    }
}
