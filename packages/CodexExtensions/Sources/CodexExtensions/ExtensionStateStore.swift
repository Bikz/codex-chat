import Foundation

public actor ExtensionStateStore {
    public init() {}

    private func stateDirectoryURL(modDirectory: URL) -> URL {
        modDirectory
            .appendingPathComponent(".codexchat", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
    }

    public func modsBarURL(modDirectory: URL, threadID: UUID) -> URL {
        stateDirectoryURL(modDirectory: modDirectory)
            .appendingPathComponent("modsBar-\(threadID.uuidString).md", isDirectory: false)
    }

    public func globalModsBarURL(modDirectory: URL) -> URL {
        stateDirectoryURL(modDirectory: modDirectory)
            .appendingPathComponent("modsBar-global.md", isDirectory: false)
    }

    public func modsBarOutputURL(
        modDirectory: URL,
        scope: ExtensionModsBarOutput.Scope,
        threadID: UUID?
    ) -> URL {
        switch scope {
        case .global:
            return stateDirectoryURL(modDirectory: modDirectory)
                .appendingPathComponent("modsBar-global.json", isDirectory: false)
        case .thread:
            let resolvedThreadID = threadID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            return stateDirectoryURL(modDirectory: modDirectory)
                .appendingPathComponent("modsBar-\(resolvedThreadID.uuidString).json", isDirectory: false)
        }
    }

    public func writeModsBarOutput(
        output: ExtensionModsBarOutput,
        modDirectory: URL,
        threadID: UUID?
    ) throws -> URL {
        let scope = output.scope ?? .thread
        guard scope == .global || threadID != nil else {
            throw NSError(
                domain: "CodexExtensions.ExtensionStateStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Thread-scoped modsBar output requires a thread ID."]
            )
        }
        let url = modsBarOutputURL(modDirectory: modDirectory, scope: scope, threadID: threadID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(output)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func readModsBarOutput(
        modDirectory: URL,
        scope: ExtensionModsBarOutput.Scope,
        threadID: UUID?
    ) throws -> ExtensionModsBarOutput? {
        let url = modsBarOutputURL(modDirectory: modDirectory, scope: scope, threadID: threadID)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ExtensionModsBarOutput.self, from: data)
        }

        // Backward compatibility fallback for markdown-only cache files.
        if scope == .thread, let threadID {
            let markdown = try readModsBar(modDirectory: modDirectory, threadID: threadID)
            if let markdown {
                return ExtensionModsBarOutput(markdown: markdown, scope: .thread)
            }
        } else if scope == .global {
            let markdown = try readGlobalModsBar(modDirectory: modDirectory)
            if let markdown {
                return ExtensionModsBarOutput(markdown: markdown, scope: .global)
            }
        }

        return nil
    }

    public func writeGlobalModsBar(markdown: String, modDirectory: URL) throws -> URL {
        let url = globalModsBarURL(modDirectory: modDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: url, options: [.atomic])
        return url
    }

    public func readGlobalModsBar(modDirectory: URL) throws -> String? {
        let url = globalModsBarURL(modDirectory: modDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
    }

    public func writeModsBar(markdown: String, modDirectory: URL, threadID: UUID) throws -> URL {
        let url = modsBarURL(modDirectory: modDirectory, threadID: threadID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: url, options: [.atomic])
        return url
    }

    public func readModsBar(modDirectory: URL, threadID: UUID) throws -> String? {
        let url = modsBarURL(modDirectory: modDirectory, threadID: threadID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
    }

    public func appendRuntimeLog(line: String, modDirectory: URL) throws -> URL {
        let url = stateDirectoryURL(modDirectory: modDirectory)
            .appendingPathComponent("runtime.log", isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let handle: FileHandle
        if FileManager.default.fileExists(atPath: url.path) {
            handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }
        defer { try? handle.close() }

        let block = "\(line.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        if let data = block.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
        return url
    }
}
