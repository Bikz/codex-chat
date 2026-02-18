import Foundation

#if canImport(NaturalLanguage)
    import NaturalLanguage
#endif

public actor ProjectMemoryStore {
    private struct SemanticIndexFile: Codable, Hashable, Sendable {
        struct SourceSignature: Codable, Hashable, Sendable {
            var fileKind: MemoryFileKind
            var modifiedAt: TimeInterval
            var size: Int
        }

        struct Entry: Codable, Hashable, Sendable {
            var fileKind: MemoryFileKind
            var text: String
            var embeddingBase64: String
        }

        var version: Int
        var sources: [SourceSignature]
        var entries: [Entry]
    }

    private let fileManager: FileManager
    private let projectURL: URL
    private let memoryRootURL: URL
    private let semanticIndexURL: URL

    public init(projectPath: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        memoryRootURL = projectURL.appendingPathComponent("memory", isDirectory: true)
        semanticIndexURL = memoryRootURL.appendingPathComponent(".semantic-index.json")
    }

    public nonisolated var memoryDirectoryPath: String {
        memoryRootURL.path
    }

    public func ensureStructure() throws {
        try fileManager.createDirectory(at: memoryRootURL, withIntermediateDirectories: true)
        for kind in MemoryFileKind.allCases {
            _ = try ensureFileExists(kind)
        }
    }

    public func filePath(for kind: MemoryFileKind) throws -> String {
        try ensureFileExists(kind).path
    }

    public func read(_ kind: MemoryFileKind) throws -> String {
        let url = try ensureFileExists(kind)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MemoryStoreError.invalidUTF8(path: url.path)
        }
        return text
    }

    public func write(_ kind: MemoryFileKind, text: String) throws {
        let url = try ensureFileExists(kind)
        let data = Data(text.utf8)
        try data.write(to: url, options: [.atomic])
    }

    public func appendToSummaryLog(markdown: String) throws {
        let url = try ensureFileExists(.summaryLog)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()

        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = trimmed.isEmpty ? "" : "\(trimmed)\n\n"
        if let data = block.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    public func deleteAllMemoryFiles() throws {
        guard fileManager.fileExists(atPath: memoryRootURL.path) else {
            return
        }
        try fileManager.removeItem(at: memoryRootURL)
    }

    public func wipeSemanticIndex() throws {
        guard fileManager.fileExists(atPath: semanticIndexURL.path) else {
            return
        }
        try fileManager.removeItem(at: semanticIndexURL)
    }

    public func keywordSearch(query: String, limit: Int = 25) throws -> [MemorySearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var hits: [MemorySearchHit] = []
        for kind in MemoryFileKind.allCases {
            if hits.count >= limit { break }
            let content = try read(kind)
            let matches = keywordHits(in: content, query: trimmed, remaining: limit - hits.count)
            hits.append(contentsOf: matches.map { excerpt in
                MemorySearchHit(fileKind: kind, excerpt: excerpt)
            })
        }
        return hits
    }

    public func semanticSearch(query: String, limit: Int = 10) throws -> [MemorySearchHit] {
        #if canImport(NaturalLanguage)
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }

            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw MemoryStoreError.semanticSearchUnavailable
            }

            let index = try loadOrBuildSemanticIndex(using: embedding)
            guard let queryVector = embedding.vector(for: trimmed) else {
                return []
            }

            let normalizedQuery = normalize(vector: queryVector)
            var scored: [(hit: MemorySearchHit, score: Double)] = []
            scored.reserveCapacity(index.entries.count)

            for entry in index.entries {
                guard let entryVector = decodeVector(entry.embeddingBase64) else { continue }
                let score = cosineSimilarity(normalizedQuery, entryVector)
                scored.append((MemorySearchHit(fileKind: entry.fileKind, excerpt: entry.text, score: score), score))
            }

            let top = scored
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map(\.hit)

            return Array(top)
        #else
            throw MemoryStoreError.semanticSearchUnavailable
        #endif
    }

    private func ensureFileExists(_ kind: MemoryFileKind) throws -> URL {
        try fileManager.createDirectory(at: memoryRootURL, withIntermediateDirectories: true)
        let url = memoryRootURL.appendingPathComponent(kind.fileName)
        if fileManager.fileExists(atPath: url.path) {
            return url
        }
        let data = Data(kind.defaultContents.utf8)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func keywordHits(in content: String, query: String, remaining: Int) -> [String] {
        guard remaining > 0 else { return [] }

        let ns = content as NSString
        var searchRange = NSRange(location: 0, length: ns.length)
        var excerpts: [String] = []

        while excerpts.count < remaining {
            let found = ns.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            if found.location == NSNotFound {
                break
            }

            let context = 90
            let start = max(0, found.location - context)
            let end = min(ns.length, found.location + found.length + context)
            let excerptRange = NSRange(location: start, length: end - start)
            let excerpt = ns.substring(with: excerptRange)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            excerpts.append(Self.collapsed(excerpt, limit: 220))

            let nextLocation = found.location + max(found.length, 1)
            if nextLocation >= ns.length {
                break
            }
            searchRange = NSRange(location: nextLocation, length: ns.length - nextLocation)
        }

        return excerpts
    }

    // MARK: - Semantic Index

    #if canImport(NaturalLanguage)
        private func loadOrBuildSemanticIndex(using embedding: NLEmbedding) throws -> SemanticIndexFile {
            try ensureStructure()

            let currentSources = try currentSourceSignatures()
            if let existing = try loadSemanticIndex(), existing.version == 1, existing.sources == currentSources {
                return existing
            }

            let built = try buildSemanticIndex(using: embedding, sources: currentSources)
            try saveSemanticIndex(built)
            return built
        }

        private func currentSourceSignatures() throws -> [SemanticIndexFile.SourceSignature] {
            var signatures: [SemanticIndexFile.SourceSignature] = []
            signatures.reserveCapacity(MemoryFileKind.allCases.count)

            for kind in MemoryFileKind.allCases {
                let url = try ensureFileExists(kind)
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                let modifiedAt = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let size = attrs[.size] as? Int ?? 0
                signatures.append(.init(fileKind: kind, modifiedAt: modifiedAt, size: size))
            }

            return signatures.sorted { $0.fileKind.rawValue < $1.fileKind.rawValue }
        }

        private func loadSemanticIndex() throws -> SemanticIndexFile? {
            guard fileManager.fileExists(atPath: semanticIndexURL.path) else {
                return nil
            }
            let data = try Data(contentsOf: semanticIndexURL)
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(SemanticIndexFile.self, from: data)
            } catch {
                throw MemoryStoreError.semanticIndexCorrupt(error.localizedDescription)
            }
        }

        private func saveSemanticIndex(_ index: SemanticIndexFile) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(index)
            try data.write(to: semanticIndexURL, options: [.atomic])
        }

        private func buildSemanticIndex(using embedding: NLEmbedding, sources: [SemanticIndexFile.SourceSignature]) throws -> SemanticIndexFile {
            var entries: [SemanticIndexFile.Entry] = []
            entries.reserveCapacity(64)

            for kind in MemoryFileKind.allCases {
                let text = try read(kind)
                let chunks = Self.chunk(text: text, maxCharacters: 600)
                for chunk in chunks {
                    guard let vector = embedding.vector(for: chunk) else { continue }
                    let normalized = normalize(vector: vector)
                    let base64 = encodeVector(normalized)
                    entries.append(.init(fileKind: kind, text: chunk, embeddingBase64: base64))
                    if entries.count >= 240 {
                        break
                    }
                }
                if entries.count >= 240 {
                    break
                }
            }

            return SemanticIndexFile(version: 1, sources: sources, entries: entries)
        }
    #endif

    // MARK: - Vector Utils

    private func normalize(vector: [Double]) -> [Float] {
        var floats = vector.map { Float($0) }
        let norm = sqrt(floats.reduce(Float(0)) { $0 + ($1 * $1) })
        guard norm > 0 else { return floats }
        for index in floats.indices {
            floats[index] /= norm
        }
        return floats
    }

    private func encodeVector(_ vector: [Float]) -> String {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer).base64EncodedString()
        }
    }

    private func decodeVector(_ base64: String) -> [Float]? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }

        var dot: Float = 0
        for idx in 0 ..< count {
            dot += lhs[idx] * rhs[idx]
        }
        return Double(dot)
    }

    // MARK: - Chunking

    private static func chunk(text: String, maxCharacters: Int) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        chunks.reserveCapacity(parts.count)

        for part in parts {
            if part.count <= maxCharacters {
                chunks.append(part)
                continue
            }

            let ns = part as NSString
            var offset = 0
            while offset < ns.length {
                let length = min(maxCharacters, ns.length - offset)
                let sub = ns.substring(with: NSRange(location: offset, length: length))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !sub.isEmpty {
                    chunks.append(sub)
                }
                offset += length
                if chunks.count >= 260 {
                    break
                }
            }

            if chunks.count >= 260 {
                break
            }
        }

        return chunks
    }

    private static func collapsed(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(0, limit - 1))) + "…"
    }
}
