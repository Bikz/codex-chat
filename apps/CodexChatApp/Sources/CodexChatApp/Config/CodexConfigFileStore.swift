import CryptoKit
import Foundation
import TOMLKit

struct CodexConfigSaveResult: Hashable, Sendable {
    let hash: String
    let modifiedAt: Date?
}

enum CodexConfigFileStoreError: LocalizedError {
    case parseError(String)
    case rootNotObject

    var errorDescription: String? {
        switch self {
        case let .parseError(detail):
            "Failed to parse config.toml: \(detail)"
        case .rootNotObject:
            "config.toml root must be a table."
        }
    }
}

struct CodexConfigFileStore {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> CodexConfigDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return CodexConfigDocument.empty()
        }

        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)

        do {
            var document = try CodexConfigDocument.parse(rawText: text)
            document.fileHash = Self.sha256(data)
            document.fileModifiedAt = modificationDate(for: fileURL)
            return document
        } catch let parseError as TOMLParseError {
            throw CodexConfigFileStoreError.parseError(parseError.humanDescription)
        } catch {
            throw error
        }
    }

    @discardableResult
    func save(document: CodexConfigDocument) throws -> CodexConfigSaveResult {
        guard document.root.objectValue != nil else {
            throw CodexConfigFileStoreError.rootNotObject
        }

        var writableDocument = document
        try writableDocument.syncRawFromRoot()
        let data = Data(writableDocument.rawText.utf8)

        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("config.toml.bak", isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try? fileManager.replaceItemAt(backupURL, withItemAt: fileURL)
        }

        let temporaryURL = directoryURL.appendingPathComponent("config.toml.tmp.\(UUID().uuidString)", isDirectory: false)

        do {
            try data.write(to: temporaryURL, options: [.atomic])
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
            try? fileManager.removeItem(at: backupURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if fileManager.fileExists(atPath: backupURL.path) {
                _ = try? fileManager.replaceItemAt(fileURL, withItemAt: backupURL)
            }
            throw error
        }

        let hash = Self.sha256(data)
        return CodexConfigSaveResult(hash: hash, modifiedAt: modificationDate(for: fileURL))
    }

    private func modificationDate(for url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
