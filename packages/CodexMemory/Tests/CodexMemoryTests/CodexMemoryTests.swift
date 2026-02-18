@testable import CodexMemory
import Foundation
import XCTest

final class CodexMemoryTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexMemoryPackage.version, "0.1.0")
    }

    func testEnsureStructureCreatesDefaultFiles() async throws {
        let projectURL = try temporaryProjectDirectory()
        let store = ProjectMemoryStore(projectPath: projectURL.path)

        try await store.ensureStructure()

        for kind in MemoryFileKind.allCases {
            let contents = try await store.read(kind)
            XCTAssertFalse(contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let path = try await store.filePath(for: kind)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }
    }

    func testAppendToSummaryLogAppendsMarkdown() async throws {
        let projectURL = try temporaryProjectDirectory()
        let store = ProjectMemoryStore(projectPath: projectURL.path)

        try await store.ensureStructure()
        try await store.appendToSummaryLog(markdown: "## Turn 1\n\nSummary: hello")
        try await store.appendToSummaryLog(markdown: "## Turn 2\n\nSummary: world")

        let log = try await store.read(.summaryLog)
        XCTAssertTrue(log.contains("## Turn 1"))
        XCTAssertTrue(log.contains("## Turn 2"))
    }

    func testKeywordSearchFindsExcerpt() async throws {
        let projectURL = try temporaryProjectDirectory()
        let store = ProjectMemoryStore(projectPath: projectURL.path)

        try await store.ensureStructure()
        try await store.write(.profile, text: "# Profile\n\nMy name is Bikram.\nI like SwiftUI.\n")
        try await store.write(.current, text: "# Current\n\nWorking on memory system.\n")

        let hits = try await store.keywordSearch(query: "swiftui", limit: 10)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.contains(where: { $0.fileKind == .profile }))
    }

    func testForgetDeletesMemoryFolder() async throws {
        let projectURL = try temporaryProjectDirectory()
        let store = ProjectMemoryStore(projectPath: projectURL.path)

        try await store.ensureStructure()
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("memory").path))

        try await store.deleteAllMemoryFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("memory").path))
    }

    func testSemanticSearchBuildsIndexWhenAvailable() async throws {
        #if canImport(NaturalLanguage)
            let projectURL = try temporaryProjectDirectory()
            let store = ProjectMemoryStore(projectPath: projectURL.path)

            try await store.ensureStructure()
            try await store.write(.profile, text: "# Profile\n\nI prefer SwiftUI.\n")

            let hits = try await store.semanticSearch(query: "SwiftUI", limit: 5)
            XCTAssertFalse(hits.isEmpty)
        #else
            throw XCTSkip("NaturalLanguage not available")
        #endif
    }

    private func temporaryProjectDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codexmemory-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
