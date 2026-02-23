import CodexChatCore
@testable import CodexChatInfra
import Foundation
import XCTest

final class SQLiteFollowUpQueueFairnessTests: XCTestCase {
    func testHighFanOutBatchSelectsAtMostOneCandidatePerThread() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Follow-Up Fairness",
            path: "/tmp/follow-up-fairness",
            trustState: .trusted,
            isGeneralProject: false
        )

        let preferredThread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Preferred"
        )

        var siblingThreads: [ThreadRecord] = []
        for index in 0 ..< 20 {
            let thread = try await repositories.threadRepository.createThread(
                projectID: project.id,
                title: "Sibling \(index)"
            )
            siblingThreads.append(thread)
        }

        var createdAtOffset = 0
        for itemIndex in 0 ..< 5 {
            try await repositories.followUpQueueRepository.enqueue(
                makeItem(
                    threadID: preferredThread.id,
                    text: "preferred-\(itemIndex)",
                    sortIndex: itemIndex,
                    createdAtOffset: createdAtOffset
                )
            )
            createdAtOffset += 1
        }

        for (index, thread) in siblingThreads.enumerated() {
            try await repositories.followUpQueueRepository.enqueue(
                makeItem(
                    threadID: thread.id,
                    text: "sibling-\(index)",
                    sortIndex: 0,
                    createdAtOffset: createdAtOffset
                )
            )
            createdAtOffset += 1
        }

        let batch = try await repositories.followUpQueueRepository.listNextAutoCandidates(
            preferredThreadID: preferredThread.id,
            excludingThreadIDs: [],
            limit: 8
        )

        XCTAssertEqual(batch.count, 8)
        XCTAssertEqual(batch.first?.threadID, preferredThread.id)
        XCTAssertEqual(Set(batch.map(\.threadID)).count, 8)
        XCTAssertEqual(batch.count(where: { $0.threadID == preferredThread.id }), 1)
    }

    func testRepeatedBatchesDoNotStarveNonPreferredThreads() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Follow-Up Starvation",
            path: "/tmp/follow-up-starvation",
            trustState: .trusted,
            isGeneralProject: false
        )

        let preferredThread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Preferred"
        )

        var siblingThreads: [ThreadRecord] = []
        for index in 0 ..< 12 {
            let thread = try await repositories.threadRepository.createThread(
                projectID: project.id,
                title: "Sibling \(index)"
            )
            siblingThreads.append(thread)
        }

        var createdAtOffset = 0
        for itemIndex in 0 ..< 20 {
            try await repositories.followUpQueueRepository.enqueue(
                makeItem(
                    threadID: preferredThread.id,
                    text: "preferred-\(itemIndex)",
                    sortIndex: itemIndex,
                    createdAtOffset: createdAtOffset
                )
            )
            createdAtOffset += 1
        }

        for (index, thread) in siblingThreads.enumerated() {
            try await repositories.followUpQueueRepository.enqueue(
                makeItem(
                    threadID: thread.id,
                    text: "sibling-\(index)",
                    sortIndex: 0,
                    createdAtOffset: createdAtOffset
                )
            )
            createdAtOffset += 1
        }

        var servedSiblingThreadIDs: Set<UUID> = []

        for _ in 0 ..< 4 {
            let batch = try await repositories.followUpQueueRepository.listNextAutoCandidates(
                preferredThreadID: preferredThread.id,
                excludingThreadIDs: [],
                limit: 4
            )

            XCTAssertEqual(batch.count, 4)
            XCTAssertEqual(Set(batch.map(\.threadID)).count, 4)
            XCTAssertEqual(batch.count(where: { $0.threadID == preferredThread.id }), 1)

            for candidate in batch where candidate.threadID != preferredThread.id {
                servedSiblingThreadIDs.insert(candidate.threadID)
            }

            for candidate in batch {
                try await repositories.followUpQueueRepository.delete(id: candidate.id)
            }
        }

        XCTAssertEqual(servedSiblingThreadIDs.count, siblingThreads.count)
    }

    private func makeItem(
        threadID: UUID,
        text: String,
        sortIndex: Int,
        createdAtOffset: Int
    ) -> FollowUpQueueItemRecord {
        let createdAt = Date(timeIntervalSince1970: 1_700_300_000 + TimeInterval(createdAtOffset))
        return FollowUpQueueItemRecord(
            threadID: threadID,
            source: .userQueued,
            dispatchMode: .auto,
            text: text,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-followup-fairness-\(UUID().uuidString).sqlite")
    }
}
