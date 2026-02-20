@testable import CodexChatCore
import Foundation
import XCTest

final class CodexChatCoreTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexChatCorePackage.version, "0.1.0")
    }

    func testListNextAutoCandidatesRespectsExclusionsAndLimit() async throws {
        let threadA = UUID()
        let threadB = UUID()
        let threadC = UUID()
        let repository = FollowUpQueueRepositoryStub(candidates: [
            FollowUpQueueItemRecord(
                threadID: threadA,
                source: .userQueued,
                dispatchMode: .auto,
                text: "A",
                sortIndex: 0
            ),
            FollowUpQueueItemRecord(
                threadID: threadB,
                source: .userQueued,
                dispatchMode: .auto,
                text: "B",
                sortIndex: 0
            ),
            FollowUpQueueItemRecord(
                threadID: threadC,
                source: .userQueued,
                dispatchMode: .auto,
                text: "C",
                sortIndex: 0
            ),
        ])

        let nextCandidates = try await repository.listNextAutoCandidates(
            preferredThreadID: threadA,
            excludingThreadIDs: [threadA],
            limit: 2
        )

        XCTAssertEqual(nextCandidates.count, 2)
        XCTAssertEqual(nextCandidates.map(\.threadID), [threadB, threadC])
    }
}

private final class FollowUpQueueRepositoryStub: FollowUpQueueRepository, @unchecked Sendable {
    private let candidates: [FollowUpQueueItemRecord]

    init(candidates: [FollowUpQueueItemRecord]) {
        self.candidates = candidates
    }

    func list(threadID _: UUID) async throws -> [FollowUpQueueItemRecord] {
        []
    }

    func listNextAutoCandidate(preferredThreadID: UUID?) async throws -> FollowUpQueueItemRecord? {
        try await listNextAutoCandidate(preferredThreadID: preferredThreadID, excludingThreadIDs: [])
    }

    func listNextAutoCandidate(
        preferredThreadID: UUID?,
        excludingThreadIDs: Set<UUID>
    ) async throws -> FollowUpQueueItemRecord? {
        if let preferredThreadID {
            if let preferred = candidates.first(where: { $0.threadID == preferredThreadID && !excludingThreadIDs.contains($0.threadID) }) {
                return preferred
            }
        }

        return candidates.first(where: { !excludingThreadIDs.contains($0.threadID) })
    }

    func enqueue(_: FollowUpQueueItemRecord) async throws {
        fatalError("Not used in this test stub.")
    }

    func updateText(id _: UUID, text _: String) async throws -> FollowUpQueueItemRecord {
        fatalError("Not used in this test stub.")
    }

    func move(id _: UUID, threadID _: UUID, toSortIndex _: Int) async throws {
        fatalError("Not used in this test stub.")
    }

    func updateDispatchMode(id _: UUID, mode _: FollowUpDispatchMode) async throws -> FollowUpQueueItemRecord {
        fatalError("Not used in this test stub.")
    }

    func markFailed(id _: UUID, error _: String) async throws {
        fatalError("Not used in this test stub.")
    }

    func markPending(id _: UUID) async throws {
        fatalError("Not used in this test stub.")
    }

    func delete(id _: UUID) async throws {
        fatalError("Not used in this test stub.")
    }
}
