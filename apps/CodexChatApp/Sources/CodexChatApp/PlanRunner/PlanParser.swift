import Foundation

enum PlanRunnerCapability: String, CaseIterable, Hashable, Sendable {
    case nativeActions = "native-actions"
    case filesystemWrite = "filesystem-write"
    case network
    case runtimeControl = "runtime-control"
}

struct PlanTask: Hashable, Sendable {
    let id: String
    let title: String
    let phaseTitle: String?
    let dependencies: [String]
    let lineNumber: Int
}

struct PlanDocument: Hashable, Sendable {
    let tasks: [PlanTask]
    let requestedCapabilities: Set<PlanRunnerCapability>

    init(tasks: [PlanTask], requestedCapabilities: Set<PlanRunnerCapability> = []) {
        self.tasks = tasks
        self.requestedCapabilities = requestedCapabilities
    }

    var taskByID: [String: PlanTask] {
        Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }
}

enum PlanParserError: LocalizedError, Sendable {
    case noTasksFound
    case duplicateTaskID(String)
    case unknownDependency(taskID: String, dependencyID: String)

    var errorDescription: String? {
        switch self {
        case .noTasksFound:
            "No tasks were found in the plan."
        case let .duplicateTaskID(taskID):
            "Duplicate task ID in plan: \(taskID)."
        case let .unknownDependency(taskID, dependencyID):
            "Task \(taskID) depends on unknown task \(dependencyID)."
        }
    }
}

enum PlanParser {
    static func parse(_ rawText: String) throws -> PlanDocument {
        let lines = rawText.components(separatedBy: .newlines)
        var currentPhaseTitle: String?
        var tasks: [PlanTask] = []
        var requestedCapabilities = Set<PlanRunnerCapability>()
        var seenTaskIDs = Set<String>()
        var lastTaskIndex: Int?

        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1

            if let parsedCapabilities = parseCapabilitiesLine(line), !parsedCapabilities.isEmpty {
                requestedCapabilities.formUnion(parsedCapabilities)
                continue
            }

            if let heading = parseHeading(line) {
                currentPhaseTitle = heading
                lastTaskIndex = nil
                continue
            }

            if let parsedTask = parseTaskLine(line) {
                if seenTaskIDs.contains(parsedTask.id) {
                    throw PlanParserError.duplicateTaskID(parsedTask.id)
                }

                var title = parsedTask.title
                let inlineDependencies = extractInlineDependencies(from: &title)
                let task = PlanTask(
                    id: parsedTask.id,
                    title: title,
                    phaseTitle: currentPhaseTitle,
                    dependencies: inlineDependencies,
                    lineNumber: lineNumber
                )
                tasks.append(task)
                seenTaskIDs.insert(parsedTask.id)
                lastTaskIndex = tasks.count - 1
                continue
            }

            if let lastTaskIndex,
               let dependencyTokens = parseDependencyLine(line),
               !dependencyTokens.isEmpty
            {
                tasks[lastTaskIndex] = mergeDependencies(
                    task: tasks[lastTaskIndex],
                    additionalDependencies: dependencyTokens
                )
            }
        }

        guard !tasks.isEmpty else {
            throw PlanParserError.noTasksFound
        }

        let knownTaskIDs = Set(tasks.map(\.id))
        for task in tasks {
            for dependencyID in task.dependencies where !knownTaskIDs.contains(dependencyID) {
                throw PlanParserError.unknownDependency(taskID: task.id, dependencyID: dependencyID)
            }
        }

        return PlanDocument(tasks: tasks, requestedCapabilities: requestedCapabilities)
    }

    private struct ParsedTaskLine {
        let id: String
        let title: String
    }

    private static let headingRegex = makeRegex(#"^\s*#{1,6}\s+(.+?)\s*$"#)
    private static let taskRegexes: [NSRegularExpression] = [
        makeRegex(#"^\s*[-*]\s*(?:\[[ xX]\]\s*)?(?:Task\s+)?([A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*)[:.)-]?\s+(.+?)\s*$"#),
        makeRegex(#"^\s*\d+[.)]\s*(?:Task\s+)?([A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*)[:.)-]?\s+(.+?)\s*$"#),
        makeRegex(#"^\s*Task\s+([A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*)[:.)-]?\s+(.+?)\s*$"#),
    ]
    private static let dependencyRegex = makeRegex(#"(?i)\b(?:depends\s+on|dependencies?)\s*[:=-]\s*(.+)$"#)
    private static let taskIDTokenRegex = makeRegex(#"[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*"#)
    private static let capabilityLineRegex = makeRegex(#"(?i)^\s*(?:plan[\s_-]*runner[\s_-]*)?capabilities?\s*:\s*(.+?)\s*$"#)
    private static let atCapabilityRegex = makeRegex(#"(?i)^\s*@capability\s+(.+?)\s*$"#)

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            fatalError("Invalid regex pattern '\(pattern)': \(error)")
        }
    }

    private static func parseHeading(_ line: String) -> String? {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        guard let match = headingRegex.firstMatch(in: line, options: [], range: range),
              let titleRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func parseTaskLine(_ line: String) -> ParsedTaskLine? {
        let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedLine.hasPrefix("- depends")
            || normalizedLine.hasPrefix("* depends")
            || normalizedLine.hasPrefix("- dependencies")
            || normalizedLine.hasPrefix("* dependencies")
        {
            return nil
        }

        let fullRange = NSRange(line.startIndex ..< line.endIndex, in: line)

        for regex in taskRegexes {
            guard let match = regex.firstMatch(in: line, options: [], range: fullRange),
                  let idRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }

            let taskID = String(line[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !taskID.isEmpty, !title.isEmpty else {
                continue
            }

            return ParsedTaskLine(id: taskID, title: title)
        }

        return nil
    }

    private static func parseCapabilitiesLine(_ line: String) -> Set<PlanRunnerCapability>? {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        let payload: String
        if let match = capabilityLineRegex.firstMatch(in: line, options: [], range: range),
           let payloadRange = Range(match.range(at: 1), in: line)
        {
            payload = String(line[payloadRange])
        } else if let match = atCapabilityRegex.firstMatch(in: line, options: [], range: range),
                  let payloadRange = Range(match.range(at: 1), in: line)
        {
            payload = String(line[payloadRange])
        } else {
            return nil
        }

        let tokens = payload
            .split { $0 == "," || $0 == "|" || $0 == ";" || $0.isWhitespace }
            .map { String($0) }

        var capabilities = Set<PlanRunnerCapability>()
        for token in tokens {
            let normalized = token
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: ".", with: "-")
            guard !normalized.isEmpty else { continue }
            switch normalized {
            case "native-action", "native-actions", "computer-action", "computer-actions":
                capabilities.insert(.nativeActions)
            case "filesystem-write", "filesystem-writes", "file-write", "file-writes", "project-write", "project-writes":
                capabilities.insert(.filesystemWrite)
            case "network":
                capabilities.insert(.network)
            case "runtime-control", "runtime":
                capabilities.insert(.runtimeControl)
            default:
                continue
            }
        }
        return capabilities
    }

    private static func parseDependencyLine(_ line: String) -> [String]? {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        guard let match = dependencyRegex.firstMatch(in: line, options: [], range: range),
              let dependenciesRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return taskIdentifiers(in: String(line[dependenciesRange]))
    }

    private static func extractInlineDependencies(from title: inout String) -> [String] {
        let range = NSRange(title.startIndex ..< title.endIndex, in: title)
        guard let match = dependencyRegex.firstMatch(in: title, options: [], range: range),
              let dependencyRange = Range(match.range(at: 1), in: title)
        else {
            return []
        }

        let dependencyText = String(title[dependencyRange])
        if let matchRange = Range(match.range, in: title) {
            title.removeSubrange(matchRange)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-,:;()[]"))
        }

        return taskIdentifiers(in: dependencyText)
    }

    private static func taskIdentifiers(in text: String) -> [String] {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        let matches = taskIDTokenRegex.matches(in: text, options: [], range: range)

        var identifiers: [String] = []
        var seen = Set<String>()
        for match in matches {
            guard let tokenRange = Range(match.range, in: text) else {
                continue
            }

            let token = String(text[tokenRange])
            guard token.rangeOfCharacter(from: .decimalDigits) != nil else {
                continue
            }
            if seen.insert(token).inserted {
                identifiers.append(token)
            }
        }

        return identifiers
    }

    private static func mergeDependencies(task: PlanTask, additionalDependencies: [String]) -> PlanTask {
        var seen = Set(task.dependencies)
        var merged = task.dependencies

        for dependency in additionalDependencies where seen.insert(dependency).inserted {
            merged.append(dependency)
        }

        return PlanTask(
            id: task.id,
            title: task.title,
            phaseTitle: task.phaseTitle,
            dependencies: merged,
            lineNumber: task.lineNumber
        )
    }
}
