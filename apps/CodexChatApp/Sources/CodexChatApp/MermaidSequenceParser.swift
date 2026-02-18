import Foundation

struct MermaidSequenceParticipant: Hashable {
    let id: String
    let displayName: String
}

struct MermaidSequenceMessage: Hashable {
    let fromID: String
    let toID: String
    let arrow: String
    let text: String
}

struct MermaidSequenceDiagram: Hashable {
    let participants: [MermaidSequenceParticipant]
    let messages: [MermaidSequenceMessage]
}

enum MermaidSequenceParser {
    static func parse(_ source: String) -> MermaidSequenceDiagram? {
        let rawLines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let first = lines.first,
              first.lowercased().hasPrefix("sequencediagram")
        else {
            return nil
        }

        var participantsByID: [String: String] = [:]
        var participantOrder: [String] = []
        var messages: [MermaidSequenceMessage] = []

        func registerParticipant(id: String, displayName: String? = nil) {
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else { return }

            if participantsByID[normalizedID] == nil {
                participantOrder.append(normalizedID)
            }

            let preferredName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let preferredName,
               !preferredName.isEmpty
            {
                participantsByID[normalizedID] = preferredName
            } else if participantsByID[normalizedID] == nil {
                participantsByID[normalizedID] = normalizedID
            }
        }

        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("participant ") {
                let remainder = line.dropFirst("participant ".count)
                if let range = remainder.range(of: " as ") {
                    let id = String(remainder[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = String(remainder[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    registerParticipant(id: id, displayName: name)
                } else {
                    let id = String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
                    registerParticipant(id: id, displayName: id)
                }
                continue
            }

            guard let message = parseMessageLine(line) else {
                continue
            }

            registerParticipant(id: message.fromID)
            registerParticipant(id: message.toID)
            messages.append(message)
        }

        let participants = participantOrder.map { id in
            MermaidSequenceParticipant(id: id, displayName: participantsByID[id] ?? id)
        }

        if participants.isEmpty, messages.isEmpty {
            return nil
        }

        return MermaidSequenceDiagram(participants: participants, messages: messages)
    }

    private static func parseMessageLine(_ line: String) -> MermaidSequenceMessage? {
        let pattern = #"^\s*([A-Za-z0-9_]+)\s*([-.]+>>?)\s*([A-Za-z0-9_]+)\s*:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5,
              let fromRange = Range(match.range(at: 1), in: line),
              let arrowRange = Range(match.range(at: 2), in: line),
              let toRange = Range(match.range(at: 3), in: line),
              let textRange = Range(match.range(at: 4), in: line)
        else {
            return nil
        }

        return MermaidSequenceMessage(
            fromID: String(line[fromRange]),
            toID: String(line[toRange]),
            arrow: String(line[arrowRange]),
            text: String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
