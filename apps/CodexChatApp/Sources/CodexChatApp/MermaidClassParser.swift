import Foundation

struct MermaidClassRelation: Hashable {
    let fromClass: String
    let relation: String
    let toClass: String
    let label: String?
}

struct MermaidClassDiagram: Hashable {
    let classes: [String]
    let relations: [MermaidClassRelation]
}

enum MermaidClassParser {
    static func parse(_ source: String) -> MermaidClassDiagram? {
        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let header = lines.first,
              header.lowercased().hasPrefix("classdiagram")
        else {
            return nil
        }

        var classOrder: [String] = []
        var seen: Set<String> = []
        var relations: [MermaidClassRelation] = []

        func registerClass(_ className: String) {
            guard !className.isEmpty else {
                return
            }

            if seen.insert(className).inserted {
                classOrder.append(className)
            }
        }

        for line in lines.dropFirst() {
            if let relation = parseRelation(from: line) {
                registerClass(relation.fromClass)
                registerClass(relation.toClass)
                relations.append(relation)
                continue
            }

            if let className = parseClassDefinition(from: line) {
                registerClass(className)
            }
        }

        if classOrder.isEmpty, relations.isEmpty {
            return nil
        }

        return MermaidClassDiagram(classes: classOrder, relations: relations)
    }

    private static func parseRelation(from line: String) -> MermaidClassRelation? {
        let pattern = #"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(<\|--|--\|>|<\|\.\.|\.\.\|>|\*--|--\*|o--|--o|-->|<--|\.\.>|<\.\.|--)\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 4,
              let fromRange = Range(match.range(at: 1), in: line),
              let relationRange = Range(match.range(at: 2), in: line),
              let toRange = Range(match.range(at: 3), in: line)
        else {
            return nil
        }

        let label: String?
        if match.numberOfRanges >= 5,
           let labelRange = Range(match.range(at: 4), in: line)
        {
            let value = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            label = value.isEmpty ? nil : value
        } else {
            label = nil
        }

        return MermaidClassRelation(
            fromClass: String(line[fromRange]),
            relation: String(line[relationRange]),
            toClass: String(line[toRange]),
            label: label
        )
    }

    private static func parseClassDefinition(from line: String) -> String? {
        if line.hasPrefix("class ") {
            let remainder = line.dropFirst("class ".count)
            let maybeClassName = remainder
                .split(separator: " ", maxSplits: 1)
                .first
                .map(String.init)
            let className = maybeClassName?.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            return className?.isEmpty == false ? className : nil
        }

        if line.hasSuffix("{") {
            let candidate = line
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isClassName(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func isClassName(_ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#) else {
            return false
        }

        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
