import Foundation

enum CodexConfigSchemaValueKind: String {
    case object
    case array
    case string
    case integer
    case number
    case boolean
    case enumeration
    case unknown
}

final class CodexConfigSchemaNode {
    var kind: CodexConfigSchemaValueKind
    var description: String?
    var required: Bool
    var enumValues: [String]
    var properties: [String: CodexConfigSchemaNode]
    var additionalProperties: CodexConfigSchemaNode?
    var items: CodexConfigSchemaNode?

    init(
        kind: CodexConfigSchemaValueKind,
        description: String? = nil,
        required: Bool = false,
        enumValues: [String] = [],
        properties: [String: CodexConfigSchemaNode] = [:],
        additionalProperties: CodexConfigSchemaNode? = nil,
        items: CodexConfigSchemaNode? = nil
    ) {
        self.kind = kind
        self.description = description
        self.required = required
        self.enumValues = enumValues
        self.properties = properties
        self.additionalProperties = additionalProperties
        self.items = items
    }

    static var unknown: CodexConfigSchemaNode {
        CodexConfigSchemaNode(kind: .unknown)
    }

    static var object: CodexConfigSchemaNode {
        CodexConfigSchemaNode(kind: .object)
    }

    func defaultValue() -> CodexConfigValue {
        switch kind {
        case .object:
            return CodexConfigValue.object([:])
        case .array:
            return CodexConfigValue.array([])
        case .string:
            return CodexConfigValue.string("")
        case .integer:
            return CodexConfigValue.integer(0)
        case .number:
            return CodexConfigValue.number(0)
        case .boolean:
            return CodexConfigValue.boolean(false)
        case .enumeration:
            if let first = enumValues.first {
                return CodexConfigValue.string(first)
            }
            return CodexConfigValue.string("")
        case .unknown:
            return CodexConfigValue.string("")
        }
    }

    func node(at path: [CodexConfigPathSegment]) -> CodexConfigSchemaNode? {
        guard let first = path.first else {
            return self
        }

        switch first {
        case let .key(key):
            if let property = properties[key] {
                return property.node(at: Array(path.dropFirst()))
            }
            if let additionalProperties {
                return additionalProperties.node(at: Array(path.dropFirst()))
            }
            return nil
        case .index:
            guard let items else {
                return nil
            }
            return items.node(at: Array(path.dropFirst()))
        }
    }
}

struct CodexConfigFormField: Identifiable {
    let path: [CodexConfigPathSegment]
    let key: String
    let schema: CodexConfigSchemaNode

    var id: String {
        (["root"] + path.map(\.display)).joined(separator: ".") + ".\(key)"
    }
}

enum CodexConfigSchemaSource: String {
    case remote
    case cache
    case bundled
}
