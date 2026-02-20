import CodexChatCore
import Foundation
import GRDB

private struct FollowUpQueueItemEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "follow_up_queue"

    var id: String
    var threadID: String
    var source: String
    var dispatchMode: String
    var state: String
    var text: String
    var sortIndex: Int
    var originTurnID: String?
    var originSuggestionID: String?
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: FollowUpQueueItemRecord) {
        id = record.id.uuidString
        threadID = record.threadID.uuidString
        source = record.source.rawValue
        dispatchMode = record.dispatchMode.rawValue
        state = record.state.rawValue
        text = record.text
        sortIndex = record.sortIndex
        originTurnID = record.originTurnID
        originSuggestionID = record.originSuggestionID
        lastError = record.lastError
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: FollowUpQueueItemRecord {
        FollowUpQueueItemRecord(
            id: UUID(uuidString: id) ?? UUID(),
            threadID: UUID(uuidString: threadID) ?? UUID(),
            source: FollowUpSource(rawValue: source) ?? .userQueued,
            dispatchMode: FollowUpDispatchMode(rawValue: dispatchMode) ?? .manual,
            state: FollowUpState(rawValue: state) ?? .pending,
            text: text,
            sortIndex: sortIndex,
            originTurnID: originTurnID,
            originSuggestionID: originSuggestionID,
            lastError: lastError,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteFollowUpQueueRepository: FollowUpQueueRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(threadID: UUID) async throws -> [FollowUpQueueItemRecord] {
        try await dbQueue.read { db in
            try Self.listEntities(db: db, threadID: threadID).map(\.record)
        }
    }

    public func listNextAutoCandidate(preferredThreadID: UUID?) async throws -> FollowUpQueueItemRecord? {
        try await listNextAutoCandidate(preferredThreadID: preferredThreadID, excludingThreadIDs: [])
    }

    public func listNextAutoCandidate(
        preferredThreadID: UUID?,
        excludingThreadIDs: Set<UUID>
    ) async throws -> FollowUpQueueItemRecord? {
        let excludedThreadIDValues = Set(excludingThreadIDs.map(\.uuidString))
        return try await dbQueue.read { db -> FollowUpQueueItemRecord? in
            if let preferredThreadID {
                let preferred = try Self.listEntities(db: db, threadID: preferredThreadID).first(where: { entity in
                    entity.state == FollowUpState.pending.rawValue
                        && entity.dispatchMode == FollowUpDispatchMode.auto.rawValue
                        && !excludedThreadIDValues.contains(entity.threadID)
                })
                if let preferred {
                    return preferred.record
                }
            }

            var request = FollowUpQueueItemEntity
                .filter(Column("state") == FollowUpState.pending.rawValue)
                .filter(Column("dispatchMode") == FollowUpDispatchMode.auto.rawValue)
                .order(Column("createdAt").asc)
                .order(Column("sortIndex").asc)

            if !excludedThreadIDValues.isEmpty {
                request = request.filter(!excludedThreadIDValues.contains(Column("threadID")))
            }

            return try request.fetchOne(db).map(\.record)
        }
    }

    public func enqueue(_ item: FollowUpQueueItemRecord) async throws {
        try await dbQueue.write { db in
            try FollowUpQueueItemEntity(record: item).insert(db)
            try Self.normalizeSortIndexes(db: db, threadID: item.threadID)
        }
    }

    public func updateText(id: UUID, text: String) async throws -> FollowUpQueueItemRecord {
        try await dbQueue.write { db in
            guard var entity = try FollowUpQueueItemEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.text = text
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func move(id: UUID, threadID: UUID, toSortIndex: Int) async throws {
        try await dbQueue.write { db in
            var entities = try Self.listEntities(db: db, threadID: threadID)
            guard let sourceIndex = entities.firstIndex(where: { $0.id == id.uuidString }) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            let moving = entities.remove(at: sourceIndex)
            let targetIndex = min(max(toSortIndex, 0), entities.count)
            entities.insert(moving, at: targetIndex)
            try Self.persistNormalized(entities: entities, in: db)
        }
    }

    public func updateDispatchMode(id: UUID, mode: FollowUpDispatchMode) async throws -> FollowUpQueueItemRecord {
        try await dbQueue.write { db in
            guard var entity = try FollowUpQueueItemEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.dispatchMode = mode.rawValue
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func markFailed(id: UUID, error: String) async throws {
        try await dbQueue.write { db in
            guard var entity = try FollowUpQueueItemEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.state = FollowUpState.failed.rawValue
            entity.lastError = error
            entity.updatedAt = Date()
            try entity.update(db)
        }
    }

    public func markPending(id: UUID) async throws {
        try await dbQueue.write { db in
            guard var entity = try FollowUpQueueItemEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.state = FollowUpState.pending.rawValue
            entity.lastError = nil
            entity.updatedAt = Date()
            try entity.update(db)
        }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            guard let entity = try FollowUpQueueItemEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            try entity.delete(db)
            if let threadID = UUID(uuidString: entity.threadID) {
                try Self.normalizeSortIndexes(db: db, threadID: threadID)
            }
        }
    }

    private static func listEntities(db: Database, threadID: UUID) throws -> [FollowUpQueueItemEntity] {
        try FollowUpQueueItemEntity
            .filter(Column("threadID") == threadID.uuidString)
            .order(Column("sortIndex").asc)
            .order(Column("createdAt").asc)
            .fetchAll(db)
    }

    private static func normalizeSortIndexes(db: Database, threadID: UUID) throws {
        let entities = try listEntities(db: db, threadID: threadID)
        try persistNormalized(entities: entities, in: db)
    }

    private static func persistNormalized(entities: [FollowUpQueueItemEntity], in db: Database) throws {
        let now = Date()
        for (index, var entity) in entities.enumerated() where entity.sortIndex != index {
            entity.sortIndex = index
            entity.updatedAt = now
            try entity.update(db)
        }
    }
}
