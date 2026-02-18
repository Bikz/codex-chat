import Foundation
import TOMLKit

struct CodexConfigDocument: Hashable, Sendable {
    var root: CodexConfigValue
    var rawText: String
    var fileHash: String
    var fileModifiedAt: Date?

    init(
        root: CodexConfigValue,
        rawText: String,
        fileHash: String,
        fileModifiedAt: Date?
    ) {
        self.root = root
        self.rawText = rawText
        self.fileHash = fileHash
        self.fileModifiedAt = fileModifiedAt
    }

    static func empty() -> CodexConfigDocument {
        CodexConfigDocument(root: .object([:]), rawText: "", fileHash: "", fileModifiedAt: nil)
    }

    func value(at path: [CodexConfigPathSegment]) -> CodexConfigValue? {
        root.value(at: path)
    }

    mutating func setValue(_ value: CodexConfigValue?, at path: [CodexConfigPathSegment]) {
        root.setValue(value, at: path)
    }

    mutating func removeValue(at path: [CodexConfigPathSegment]) {
        root.removeValue(at: path)
    }

    mutating func syncRawFromRoot() throws {
        guard let object = root.objectValue else {
            throw CodexConfigDocumentError.rootMustBeObject
        }

        let table = TOMLTable()
        for key in object.keys.sorted() {
            guard let value = object[key], value != .null else {
                continue
            }
            table[key] = value.toTOMLValue()
        }

        rawText = table.convert(to: .toml)
    }

    static func parse(rawText: String) throws -> CodexConfigDocument {
        let table = try TOMLTable(string: rawText)
        let root = CodexConfigValue.fromTOML(table)
        return CodexConfigDocument(root: root, rawText: rawText, fileHash: "", fileModifiedAt: nil)
    }
}

enum CodexConfigDocumentError: LocalizedError {
    case rootMustBeObject

    var errorDescription: String? {
        switch self {
        case .rootMustBeObject:
            "Codex config root must be a TOML table."
        }
    }
}

extension TOMLParseError {
    var humanDescription: String {
        "\(description) (line \(source.begin.line), column \(source.begin.column))"
    }
}
