import Foundation

public struct MemorySearchHit: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let fileKind: MemoryFileKind
    public let excerpt: String
    public let score: Double?

    public init(id: UUID = UUID(), fileKind: MemoryFileKind, excerpt: String, score: Double? = nil) {
        self.id = id
        self.fileKind = fileKind
        self.excerpt = excerpt
        self.score = score
    }
}

public enum MemoryStoreError: LocalizedError, Sendable {
    case invalidUTF8(path: String)
    case semanticSearchUnavailable
    case semanticIndexCorrupt(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8(let path):
            return "Memory file could not be decoded as UTF-8: \(path)"
        case .semanticSearchUnavailable:
            return "Semantic search is unavailable on this system."
        case .semanticIndexCorrupt(let detail):
            return "Semantic index is corrupt: \(detail)"
        }
    }
}

