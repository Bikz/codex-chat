import Foundation

struct CodexConfigSchemaNormalizer {
    private let rootSchema: [String: Any]
    private let definitions: [String: Any]

    init(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw CodexConfigSchemaLoaderError.invalidSchema("Root schema is not an object")
        }
        rootSchema = object
        definitions = object["definitions"] as? [String: Any] ?? [:]
    }

    func normalize() -> CodexConfigSchemaNode {
        normalizeNode(rootSchema)
    }

    private func normalizeNode(_ raw: [String: Any], required: Bool = false) -> CodexConfigSchemaNode {
        let schema = resolve(raw)

        if let oneOf = schema["oneOf"] as? [Any],
           let enumValues = collectEnumValues(fromUnion: oneOf), !enumValues.isEmpty
        {
            return CodexConfigSchemaNode(
                kind: .enumeration,
                description: schema["description"] as? String,
                required: required,
                enumValues: enumValues
            )
        }

        if let anyOf = schema["anyOf"] as? [Any],
           let enumValues = collectEnumValues(fromUnion: anyOf), !enumValues.isEmpty
        {
            return CodexConfigSchemaNode(
                kind: .enumeration,
                description: schema["description"] as? String,
                required: required,
                enumValues: enumValues
            )
        }

        if let enumValues = collectEnumValues(schema), !enumValues.isEmpty {
            return CodexConfigSchemaNode(
                kind: .enumeration,
                description: schema["description"] as? String,
                required: required,
                enumValues: enumValues
            )
        }

        let kind = detectKind(schema)
        switch kind {
        case .object:
            let requiredKeys = Set(schema["required"] as? [String] ?? [])
            var properties: [String: CodexConfigSchemaNode] = [:]
            if let rawProperties = schema["properties"] as? [String: Any] {
                for key in rawProperties.keys.sorted() {
                    if let propertySchema = rawProperties[key] as? [String: Any] {
                        properties[key] = normalizeNode(propertySchema, required: requiredKeys.contains(key))
                    }
                }
            }

            var additional: CodexConfigSchemaNode?
            if let additionalSchema = schema["additionalProperties"] as? [String: Any] {
                additional = normalizeNode(additionalSchema)
            } else if let allowAdditional = schema["additionalProperties"] as? Bool, allowAdditional {
                additional = .unknown
            }

            return CodexConfigSchemaNode(
                kind: .object,
                description: schema["description"] as? String,
                required: required,
                properties: properties,
                additionalProperties: additional
            )
        case .array:
            let itemSchema = (schema["items"] as? [String: Any]).map { normalizeNode($0) }
            return CodexConfigSchemaNode(
                kind: .array,
                description: schema["description"] as? String,
                required: required,
                items: itemSchema
            )
        case .string:
            return CodexConfigSchemaNode(kind: .string, description: schema["description"] as? String, required: required)
        case .integer:
            return CodexConfigSchemaNode(kind: .integer, description: schema["description"] as? String, required: required)
        case .number:
            return CodexConfigSchemaNode(kind: .number, description: schema["description"] as? String, required: required)
        case .boolean:
            return CodexConfigSchemaNode(kind: .boolean, description: schema["description"] as? String, required: required)
        case .enumeration:
            return CodexConfigSchemaNode(kind: .enumeration, description: schema["description"] as? String, required: required)
        case .unknown:
            return CodexConfigSchemaNode(kind: .unknown, description: schema["description"] as? String, required: required)
        }
    }

    private func resolve(_ raw: [String: Any]) -> [String: Any] {
        var schema = raw

        if let ref = schema["$ref"] as? String,
           let resolvedReference = resolveReference(ref)
        {
            schema.removeValue(forKey: "$ref")
            schema = merge(resolvedReference, with: schema)
        }

        if let allOf = schema["allOf"] as? [Any] {
            schema.removeValue(forKey: "allOf")
            for child in allOf {
                guard let childSchema = child as? [String: Any] else {
                    continue
                }
                schema = merge(schema, with: resolve(childSchema))
            }
        }

        return schema
    }

    private func resolveReference(_ ref: String) -> [String: Any]? {
        guard ref.hasPrefix("#/definitions/") else {
            return nil
        }

        let key = String(ref.dropFirst("#/definitions/".count))
        guard let definition = definitions[key] as? [String: Any] else {
            return nil
        }

        return resolve(definition)
    }

    private func merge(_ lhs: [String: Any], with rhs: [String: Any]) -> [String: Any] {
        var merged = lhs

        for (key, rhsValue) in rhs {
            if key == "required",
               let rhsRequired = rhsValue as? [String]
            {
                let lhsRequired = merged[key] as? [String] ?? []
                merged[key] = Array(Set(lhsRequired + rhsRequired)).sorted()
                continue
            }

            if key == "enum",
               let rhsEnum = rhsValue as? [Any]
            {
                let lhsEnum = merged[key] as? [Any] ?? []
                let combined = (lhsEnum + rhsEnum).map { String(describing: $0) }
                merged[key] = Array(Set(combined)).sorted()
                continue
            }

            if key == "properties",
               let lhsProps = merged[key] as? [String: Any],
               let rhsProps = rhsValue as? [String: Any]
            {
                merged[key] = lhsProps.merging(rhsProps) { left, right in
                    guard let leftSchema = left as? [String: Any],
                          let rightSchema = right as? [String: Any]
                    else {
                        return right
                    }
                    return merge(leftSchema, with: rightSchema)
                }
                continue
            }

            merged[key] = rhsValue
        }

        return merged
    }

    private func detectKind(_ schema: [String: Any]) -> CodexConfigSchemaValueKind {
        if schema["properties"] != nil || schema["additionalProperties"] != nil {
            return .object
        }

        if schema["items"] != nil {
            return .array
        }

        if let type = schema["type"] as? String {
            return kind(fromType: type)
        }

        if let types = schema["type"] as? [String],
           let first = types.first(where: { $0 != "null" })
        {
            return kind(fromType: first)
        }

        return .unknown
    }

    private func kind(fromType type: String) -> CodexConfigSchemaValueKind {
        switch type {
        case "object":
            .object
        case "array":
            .array
        case "string":
            .string
        case "integer":
            .integer
        case "number":
            .number
        case "boolean":
            .boolean
        default:
            .unknown
        }
    }

    private func collectEnumValues(_ schema: [String: Any]) -> [String]? {
        guard let enumCandidates = schema["enum"] as? [Any], !enumCandidates.isEmpty else {
            return nil
        }

        let values = enumCandidates.map { String(describing: $0) }
        return Array(Set(values)).sorted()
    }

    private func collectEnumValues(fromUnion union: [Any]) -> [String]? {
        var values: [String] = []

        for element in union {
            guard let schema = element as? [String: Any],
                  let enumValues = collectEnumValues(schema)
            else {
                return nil
            }
            values.append(contentsOf: enumValues)
        }

        guard !values.isEmpty else {
            return nil
        }

        return Array(Set(values)).sorted()
    }
}
