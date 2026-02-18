import CodexChatCore
import Foundation
import GRDB

public final class SQLiteChatSearchRepository: ChatSearchRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func indexThreadTitle(threadID: UUID, projectID: UUID, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM chat_search_index WHERE threadID = ? AND source = 'title'",
                arguments: [threadID.uuidString]
            )
            try db.execute(
                sql: """
                INSERT INTO chat_search_index(threadID, projectID, source, content)
                VALUES (?, ?, 'title', ?)
                """,
                arguments: [threadID.uuidString, projectID.uuidString, trimmed]
            )
        }
    }

    public func indexMessageExcerpt(threadID: UUID, projectID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO chat_search_index(threadID, projectID, source, content)
                VALUES (?, ?, 'message', ?)
                """,
                arguments: [threadID.uuidString, projectID.uuidString, trimmed]
            )
        }
    }

    public func search(query: String, projectID: UUID?, limit: Int) async throws -> [ChatSearchResult] {
        let normalizedQuery = Self.makeFTSQuery(from: query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return try await dbQueue.read { db in
            var sql = """
            SELECT chat_search_index.threadID, chat_search_index.projectID, chat_search_index.source,
                   snippet(chat_search_index, 3, '', '', ' … ', 18) AS excerpt
            FROM chat_search_index
            JOIN threads ON threads.id = chat_search_index.threadID
            WHERE chat_search_index MATCH ?
              AND threads.archivedAt IS NULL
            """
            var arguments: StatementArguments = [normalizedQuery]

            if let projectID {
                sql += " AND chat_search_index.projectID = ?"
                arguments += [projectID.uuidString]
            }

            sql += " ORDER BY bm25(chat_search_index) LIMIT ?"
            arguments += [limit]

            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                guard let threadIDString: String = row["threadID"],
                      let projectIDString: String = row["projectID"],
                      let threadUUID = UUID(uuidString: threadIDString),
                      let projectUUID = UUID(uuidString: projectIDString)
                else {
                    return nil
                }

                let source: String = row["source"] ?? "message"
                let excerpt: String = row["excerpt"] ?? ""
                return ChatSearchResult(
                    threadID: threadUUID,
                    projectID: projectUUID,
                    source: source,
                    excerpt: excerpt
                )
            }
        }
    }

    private static func makeFTSQuery(from query: String) -> String {
        let tokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return ""
        }

        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }
}
