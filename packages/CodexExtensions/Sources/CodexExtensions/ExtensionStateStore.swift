import Foundation

public actor ExtensionStateStore {
    public init() {}

    public func inspectorURL(modDirectory: URL, threadID: UUID) -> URL {
        modDirectory
            .appendingPathComponent(".codexchat", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("inspector-\(threadID.uuidString).md", isDirectory: false)
    }

    public func writeInspector(markdown: String, modDirectory: URL, threadID: UUID) throws -> URL {
        let url = inspectorURL(modDirectory: modDirectory, threadID: threadID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: url, options: [.atomic])
        return url
    }

    public func readInspector(modDirectory: URL, threadID: UUID) throws -> String? {
        let url = inspectorURL(modDirectory: modDirectory, threadID: threadID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
    }

    public func appendRuntimeLog(line: String, modDirectory: URL) throws -> URL {
        let url = modDirectory
            .appendingPathComponent(".codexchat", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
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
