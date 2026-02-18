import Foundation

struct MermaidFlowchartNode: Hashable {
    let id: String
    let label: String
}

struct MermaidFlowchartEdge: Hashable {
    let fromID: String
    let toID: String
    let label: String?
}

struct MermaidFlowchartDiagram: Hashable {
    let direction: String
    let nodes: [MermaidFlowchartNode]
    let edges: [MermaidFlowchartEdge]
}

enum MermaidFlowchartParser {
    private struct NodeToken {
        let id: String
        let label: String?
    }

    static func parse(_ source: String) -> MermaidFlowchartDiagram? {
        let rawLines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let header = lines.first else {
            return nil
        }

        let headerTokens = header.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let directive = headerTokens.first?.lowercased(),
              directive == "graph" || directive == "flowchart"
        else {
            return nil
        }

        let direction = headerTokens.count > 1 ? headerTokens[1] : "TD"

        var labelsByNodeID: [String: String] = [:]
        var nodeOrder: [String] = []
        var edges: [MermaidFlowchartEdge] = []

        func registerNode(_ token: NodeToken) {
            guard !token.id.isEmpty else { return }
            if labelsByNodeID[token.id] == nil {
                nodeOrder.append(token.id)
            }
            let normalizedLabel = token.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedLabel,
               !normalizedLabel.isEmpty
            {
                let existing = labelsByNodeID[token.id]
                if existing == nil || (existing == token.id && normalizedLabel != token.id) {
                    labelsByNodeID[token.id] = normalizedLabel
                }
            } else if labelsByNodeID[token.id] == nil {
                labelsByNodeID[token.id] = token.id
            }
        }

        for line in lines.dropFirst() {
            let normalized = line
                .replacingOccurrences(of: "-.->", with: "-->")
                .replacingOccurrences(of: "==>", with: "-->")

            if let edgeComponents = parseEdgeLine(normalized),
               let from = parseNodeToken(edgeComponents.fromToken),
               let to = parseNodeToken(edgeComponents.toToken)
            {
                registerNode(from)
                registerNode(to)
                edges.append(
                    MermaidFlowchartEdge(
                        fromID: from.id,
                        toID: to.id,
                        label: edgeComponents.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                continue
            }

            if let node = parseNodeToken(normalized) {
                registerNode(node)
            }
        }

        let nodes = nodeOrder.map { nodeID in
            MermaidFlowchartNode(id: nodeID, label: labelsByNodeID[nodeID] ?? nodeID)
        }

        if nodes.isEmpty, edges.isEmpty {
            return nil
        }

        return MermaidFlowchartDiagram(direction: direction, nodes: nodes, edges: edges)
    }

    private static func parseEdgeLine(_ line: String) -> (fromToken: String, toToken: String, label: String?)? {
        let patterns: [(pattern: String, hasMiddleLabel: Bool, hasPipeLabel: Bool)] = [
            (#"^\s*(.+?)\s*--\s*(.+?)\s*-->\s*(.+?)\s*$"#, true, false),
            (#"^\s*(.+?)\s*-->\|(.+?)\|\s*(.+?)\s*$"#, false, true),
            (#"^\s*(.+?)\s*-->\s*(.+?)\s*$"#, false, false),
        ]

        for item in patterns {
            guard let regex = try? NSRegularExpression(pattern: item.pattern) else {
                continue
            }

            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }

            if item.hasMiddleLabel || item.hasPipeLabel {
                guard match.numberOfRanges == 4,
                      let fromRange = Range(match.range(at: 1), in: line),
                      let labelRange = Range(match.range(at: 2), in: line),
                      let toRange = Range(match.range(at: 3), in: line)
                else {
                    continue
                }

                return (
                    fromToken: String(line[fromRange]),
                    toToken: String(line[toRange]),
                    label: String(line[labelRange])
                )
            }

            guard match.numberOfRanges == 3,
                  let fromRange = Range(match.range(at: 1), in: line),
                  let toRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }

            return (
                fromToken: String(line[fromRange]),
                toToken: String(line[toRange]),
                label: nil
            )
        }

        return nil
    }

    private static func parseNodeToken(_ token: String) -> NodeToken? {
        let trimmed = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";", with: "")

        guard !trimmed.isEmpty else {
            return nil
        }

        if let bracketIndex = trimmed.firstIndex(where: { $0 == "[" || $0 == "(" || $0 == "{" }) {
            let rawID = trimmed[..<bracketIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawID.isEmpty else {
                return nil
            }

            let suffix = trimmed[bracketIndex...]
            let label = labelFromBracketedSuffix(String(suffix))
            return NodeToken(id: String(rawID), label: label)
        }

        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else {
            return nil
        }

        return NodeToken(id: compact, label: trimmed)
    }

    private static func labelFromBracketedSuffix(_ suffix: String) -> String {
        if suffix.hasPrefix("[["), suffix.hasSuffix("]]") {
            return String(suffix.dropFirst(2).dropLast(2))
        }
        if suffix.hasPrefix("["), suffix.hasSuffix("]") {
            return String(suffix.dropFirst().dropLast())
        }
        if suffix.hasPrefix("(("), suffix.hasSuffix("))") {
            return String(suffix.dropFirst(2).dropLast(2))
        }
        if suffix.hasPrefix("("), suffix.hasSuffix(")") {
            return String(suffix.dropFirst().dropLast())
        }
        if suffix.hasPrefix("{"), suffix.hasSuffix("}") {
            return String(suffix.dropFirst().dropLast())
        }
        if suffix.hasPrefix("<"), suffix.hasSuffix(">") {
            return String(suffix.dropFirst().dropLast())
        }
        return suffix
    }
}
