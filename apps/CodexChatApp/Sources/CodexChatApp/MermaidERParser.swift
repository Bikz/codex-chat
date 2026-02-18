import Foundation

struct MermaidEREntity: Hashable {
    let name: String
}

struct MermaidERRelation: Hashable {
    let leftEntity: String
    let cardinality: String
    let rightEntity: String
    let label: String
}

struct MermaidERDiagram: Hashable {
    let entities: [MermaidEREntity]
    let relations: [MermaidERRelation]
}

enum MermaidERParser {
    static func parse(_ source: String) -> MermaidERDiagram? {
        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let header = lines.first,
              header.lowercased().hasPrefix("erdiagram")
        else {
            return nil
        }

        var entityOrder: [String] = []
        var seenEntities: Set<String> = []
        var relations: [MermaidERRelation] = []

        func registerEntity(_ name: String) {
            guard !name.isEmpty else {
                return
            }

            if seenEntities.insert(name).inserted {
                entityOrder.append(name)
            }
        }

        for line in lines.dropFirst() {
            if let relation = parseRelation(from: line) {
                registerEntity(relation.leftEntity)
                registerEntity(relation.rightEntity)
                relations.append(relation)
                continue
            }

            if let entityName = parseEntityDefinition(from: line) {
                registerEntity(entityName)
            }
        }

        if entityOrder.isEmpty, relations.isEmpty {
            return nil
        }

        return MermaidERDiagram(
            entities: entityOrder.map { MermaidEREntity(name: $0) },
            relations: relations
        )
    }

    private static func parseRelation(from line: String) -> MermaidERRelation? {
        let pattern = #"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*([\|o}{]{1,2}--[\|o}{]{1,2})\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5,
              let leftRange = Range(match.range(at: 1), in: line),
              let cardinalityRange = Range(match.range(at: 2), in: line),
              let rightRange = Range(match.range(at: 3), in: line),
              let labelRange = Range(match.range(at: 4), in: line)
        else {
            return nil
        }

        let label = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            return nil
        }

        return MermaidERRelation(
            leftEntity: String(line[leftRange]),
            cardinality: String(line[cardinalityRange]),
            rightEntity: String(line[rightRange]),
            label: label
        )
    }

    private static func parseEntityDefinition(from line: String) -> String? {
        if line.hasSuffix("{") {
            let candidate = line
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return isEntityName(candidate) ? candidate : nil
        }

        return nil
    }

    private static func isEntityName(_ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#) else {
            return false
        }

        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
