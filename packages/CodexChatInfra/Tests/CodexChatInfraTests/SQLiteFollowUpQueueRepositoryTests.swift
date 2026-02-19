import CodexChatCore
@testable import CodexChatInfra
import Foundation
import XCTest

final class SQLiteFollowUpQueueRepositoryTests: XCTestCase {
    func testDeleteMissingItemThrowsMissingRecord() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-followup-delete-\(UUID().uuidString).sqlite")
        let database = try MetadataDatabase(databaseURL: databaseURL)
        let repositories = MetadataRepositories(database: database)

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        do {
            try await repositories.followUpQueueRepository.delete(id: UUID())
            XCTFail("Expected missing follow-up item deletion to throw.")
        } catch let CodexChatCoreError.missingRecord(id) {
            XCTAssertFalse(id.isEmpty)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
