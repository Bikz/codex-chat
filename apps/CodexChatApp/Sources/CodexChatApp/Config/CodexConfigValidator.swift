import Foundation

enum CodexConfigValidationSeverity: String, Sendable {
    case warning
    case error
}

struct CodexConfigValidationIssue: Identifiable, Hashable, Sendable {
    let id: UUID
    let severity: CodexConfigValidationSeverity
    let path: [CodexConfigPathSegment]
    let message: String

    init(
        id: UUID = UUID(),
        severity: CodexConfigValidationSeverity,
        path: [CodexConfigPathSegment],
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.path = path
        self.message = message
    }

    var pathLabel: String {
        if path.isEmpty {
            return "root"
        }

        return path.map(\.display).joined(separator: ".")
    }
}

struct CodexConfigValidator {
    func validate(value: CodexConfigValue, against schema: CodexConfigSchemaNode) -> [CodexConfigValidationIssue] {
        validate(value: value, schema: schema, path: [])
    }

    private func validate(
        value: CodexConfigValue,
        schema: CodexConfigSchemaNode,
        path: [CodexConfigPathSegment]
    ) -> [CodexConfigValidationIssue] {
        switch schema.kind {
        case .object:
            guard case let .object(objectValue) = value else {
                return [typeMismatch(path: path, expected: "object", actual: value)]
            }

            var issues: [CodexConfigValidationIssue] = []

            for (key, childSchema) in schema.properties {
                let childPath = path + [.key(key)]
                if let childValue = objectValue[key] {
                    issues.append(contentsOf: validate(value: childValue, schema: childSchema, path: childPath))
                } else if childSchema.required {
                    issues.append(
                        CodexConfigValidationIssue(
                            severity: .error,
                            path: childPath,
                            message: "Missing required field."
                        )
                    )
                }
            }

            for (key, childValue) in objectValue where schema.properties[key] == nil {
                let childPath = path + [.key(key)]
                if let additionalSchema = schema.additionalProperties {
                    issues.append(contentsOf: validate(value: childValue, schema: additionalSchema, path: childPath))
                } else {
                    issues.append(
                        CodexConfigValidationIssue(
                            severity: .warning,
                            path: childPath,
                            message: "Unknown key is not declared in the schema."
                        )
                    )
                }
            }

            return issues
        case .array:
            guard case let .array(arrayValue) = value else {
                return [typeMismatch(path: path, expected: "array", actual: value)]
            }

            guard let itemSchema = schema.items else {
                return []
            }

            var issues: [CodexConfigValidationIssue] = []
            for (index, childValue) in arrayValue.enumerated() {
                issues.append(
                    contentsOf: validate(
                        value: childValue,
                        schema: itemSchema,
                        path: path + [.index(index)]
                    )
                )
            }
            return issues
        case .string:
            if case .string = value {
                return []
            }
            return [typeMismatch(path: path, expected: "string", actual: value)]
        case .integer:
            if case .integer = value {
                return []
            }
            return [typeMismatch(path: path, expected: "integer", actual: value)]
        case .number:
            if case .number = value {
                return []
            }
            if case .integer = value {
                return []
            }
            return [typeMismatch(path: path, expected: "number", actual: value)]
        case .boolean:
            if case .boolean = value {
                return []
            }
            return [typeMismatch(path: path, expected: "boolean", actual: value)]
        case .enumeration:
            guard case let .string(stringValue) = value else {
                return [typeMismatch(path: path, expected: "enum", actual: value)]
            }
            guard schema.enumValues.contains(stringValue) else {
                return [
                    CodexConfigValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Value '\(stringValue)' is not in allowed values: \(schema.enumValues.joined(separator: ", "))."
                    ),
                ]
            }
            return []
        case .unknown:
            return []
        }
    }

    private func typeMismatch(path: [CodexConfigPathSegment], expected: String, actual: CodexConfigValue) -> CodexConfigValidationIssue {
        CodexConfigValidationIssue(
            severity: .error,
            path: path,
            message: "Expected \(expected), got \(actual.printableValue)."
        )
    }
}
