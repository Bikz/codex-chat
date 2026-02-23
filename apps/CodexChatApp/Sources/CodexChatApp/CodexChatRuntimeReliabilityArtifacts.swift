import CodexChatCore
import CryptoKit
import Foundation

public struct CodexChatReplayAction: Codable, Equatable, Sendable {
    public let method: String
    public let title: String
    public let detail: String
    public let createdAt: Date

    public init(method: String, title: String, detail: String, createdAt: Date) {
        self.method = method
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}

public struct CodexChatReplayTurn: Codable, Equatable, Sendable {
    public let turnID: UUID
    public let timestamp: Date
    public let status: String
    public let userText: String
    public let assistantText: String
    public let actions: [CodexChatReplayAction]

    public init(
        turnID: UUID,
        timestamp: Date,
        status: String,
        userText: String,
        assistantText: String,
        actions: [CodexChatReplayAction]
    ) {
        self.turnID = turnID
        self.timestamp = timestamp
        self.status = status
        self.userText = userText
        self.assistantText = assistantText
        self.actions = actions
    }
}

public struct CodexChatThreadReplaySummary: Codable, Equatable, Sendable {
    public let projectPath: String
    public let threadID: UUID
    public let turnCount: Int
    public let pendingTurnCount: Int
    public let failedTurnCount: Int
    public let completedTurnCount: Int
    public let turns: [CodexChatReplayTurn]

    public init(
        projectPath: String,
        threadID: UUID,
        turnCount: Int,
        pendingTurnCount: Int,
        failedTurnCount: Int,
        completedTurnCount: Int,
        turns: [CodexChatReplayTurn]
    ) {
        self.projectPath = projectPath
        self.threadID = threadID
        self.turnCount = turnCount
        self.pendingTurnCount = pendingTurnCount
        self.failedTurnCount = failedTurnCount
        self.completedTurnCount = completedTurnCount
        self.turns = turns
    }
}

public struct CodexChatThreadLedgerEntry: Codable, Equatable, Sendable {
    public let sequence: Int
    public let turnID: UUID
    public let timestamp: Date
    public let kind: String
    public let status: String?
    public let method: String?
    public let title: String?
    public let text: String?

    public init(
        sequence: Int,
        turnID: UUID,
        timestamp: Date,
        kind: String,
        status: String?,
        method: String?,
        title: String?,
        text: String?
    ) {
        self.sequence = sequence
        self.turnID = turnID
        self.timestamp = timestamp
        self.kind = kind
        self.status = status
        self.method = method
        self.title = title
        self.text = text
    }
}

public struct CodexChatThreadLedgerDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let projectPath: String
    public let threadID: UUID
    public let entries: [CodexChatThreadLedgerEntry]

    public init(
        schemaVersion: Int,
        generatedAt: Date,
        projectPath: String,
        threadID: UUID,
        entries: [CodexChatThreadLedgerEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.projectPath = projectPath
        self.threadID = threadID
        self.entries = entries
    }
}

public struct CodexChatThreadLedgerExportSummary: Codable, Equatable, Sendable {
    public let outputPath: String
    public let entryCount: Int
    public let sha256: String

    public init(outputPath: String, entryCount: Int, sha256: String) {
        self.outputPath = outputPath
        self.entryCount = entryCount
        self.sha256 = sha256
    }
}

public struct CodexChatLedgerBackfillThreadResult: Codable, Equatable, Sendable {
    public let threadID: UUID
    public let status: String
    public let ledgerPath: String
    public let markerPath: String
    public let entryCount: Int?
    public let sha256: String?

    public init(
        threadID: UUID,
        status: String,
        ledgerPath: String,
        markerPath: String,
        entryCount: Int?,
        sha256: String?
    ) {
        self.threadID = threadID
        self.status = status
        self.ledgerPath = ledgerPath
        self.markerPath = markerPath
        self.entryCount = entryCount
        self.sha256 = sha256
    }
}

public struct CodexChatLedgerBackfillSummary: Codable, Equatable, Sendable {
    public let projectPath: String
    public let markerDirectoryPath: String
    public let scannedThreadCount: Int
    public let exportedThreadCount: Int
    public let skippedThreadCount: Int
    public let threads: [CodexChatLedgerBackfillThreadResult]

    public init(
        projectPath: String,
        markerDirectoryPath: String,
        scannedThreadCount: Int,
        exportedThreadCount: Int,
        skippedThreadCount: Int,
        threads: [CodexChatLedgerBackfillThreadResult]
    ) {
        self.projectPath = projectPath
        self.markerDirectoryPath = markerDirectoryPath
        self.scannedThreadCount = scannedThreadCount
        self.exportedThreadCount = exportedThreadCount
        self.skippedThreadCount = skippedThreadCount
        self.threads = threads
    }
}

public struct CodexChatLedgerBackfillMarker: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let projectPath: String
    public let threadID: UUID
    public let ledgerPath: String
    public let entryCount: Int
    public let sha256: String

    public init(
        schemaVersion: Int,
        generatedAt: Date,
        projectPath: String,
        threadID: UUID,
        ledgerPath: String,
        entryCount: Int,
        sha256: String
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.projectPath = projectPath
        self.threadID = threadID
        self.ledgerPath = ledgerPath
        self.entryCount = entryCount
        self.sha256 = sha256
    }
}

public struct CodexChatRuntimePolicyDocument: Codable, Equatable, Sendable {
    public let version: Int
    public let defaultApprovalPolicy: String
    public let defaultSandboxMode: String
    public let allowNetworkAccess: Bool
    public let allowWebSearch: Bool
    public let allowDangerFullAccess: Bool
    public let allowNeverApproval: Bool

    public init(
        version: Int,
        defaultApprovalPolicy: String,
        defaultSandboxMode: String,
        allowNetworkAccess: Bool,
        allowWebSearch: Bool,
        allowDangerFullAccess: Bool,
        allowNeverApproval: Bool
    ) {
        self.version = version
        self.defaultApprovalPolicy = defaultApprovalPolicy
        self.defaultSandboxMode = defaultSandboxMode
        self.allowNetworkAccess = allowNetworkAccess
        self.allowWebSearch = allowWebSearch
        self.allowDangerFullAccess = allowDangerFullAccess
        self.allowNeverApproval = allowNeverApproval
    }
}

public struct CodexChatRuntimePolicyIssue: Codable, Equatable, Sendable {
    public let severity: String
    public let message: String

    public init(severity: String, message: String) {
        self.severity = severity
        self.message = message
    }
}

public struct CodexChatRuntimePolicyValidationReport: Codable, Equatable, Sendable {
    public let filePath: String
    public let isValid: Bool
    public let issues: [CodexChatRuntimePolicyIssue]
    public let document: CodexChatRuntimePolicyDocument?

    public init(
        filePath: String,
        isValid: Bool,
        issues: [CodexChatRuntimePolicyIssue],
        document: CodexChatRuntimePolicyDocument?
    ) {
        self.filePath = filePath
        self.isValid = isValid
        self.issues = issues
        self.document = document
    }
}

public extension CodexChatBootstrap {
    static func replayThread(
        projectPath: String,
        threadID: UUID,
        limit: Int = 100
    ) throws -> CodexChatThreadReplaySummary {
        guard limit > 0 else {
            throw NSError(
                domain: "CodexChatCLI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Replay limit must be a positive integer"]
            )
        }

        let normalizedProjectPath = normalizeProjectPath(projectPath)
        let turns = try ChatArchiveStore.loadRecentTurns(
            projectPath: normalizedProjectPath,
            threadID: threadID,
            limit: limit
        )

        let replayTurns = turns.map { turn in
            CodexChatReplayTurn(
                turnID: turn.turnID,
                timestamp: turn.timestamp,
                status: turn.status.rawValue,
                userText: turn.userText,
                assistantText: turn.assistantText,
                actions: turn.actions.map {
                    CodexChatReplayAction(
                        method: $0.method,
                        title: $0.title,
                        detail: $0.detail,
                        createdAt: $0.createdAt
                    )
                }
            )
        }

        let pendingCount = replayTurns.count(where: { $0.status == ChatArchiveTurnStatus.pending.rawValue })
        let failedCount = replayTurns.count(where: { $0.status == ChatArchiveTurnStatus.failed.rawValue })
        let completedCount = replayTurns.count(where: { $0.status == ChatArchiveTurnStatus.completed.rawValue })

        return CodexChatThreadReplaySummary(
            projectPath: normalizedProjectPath,
            threadID: threadID,
            turnCount: replayTurns.count,
            pendingTurnCount: pendingCount,
            failedTurnCount: failedCount,
            completedTurnCount: completedCount,
            turns: replayTurns
        )
    }

    static func exportThreadLedger(
        projectPath: String,
        threadID: UUID,
        limit: Int = 100,
        outputURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> CodexChatThreadLedgerExportSummary {
        let replay = try replayThread(projectPath: projectPath, threadID: threadID, limit: limit)
        let entries = makeLedgerEntries(turns: replay.turns)
        let ledgerDocument = CodexChatThreadLedgerDocument(
            schemaVersion: 1,
            generatedAt: Date(),
            projectPath: replay.projectPath,
            threadID: replay.threadID,
            entries: entries
        )

        let destination = outputURL ?? defaultLedgerURL(projectPath: replay.projectPath, threadID: replay.threadID)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ledgerDocument)
        try data.write(to: destination, options: .atomic)

        return CodexChatThreadLedgerExportSummary(
            outputPath: destination.path,
            entryCount: entries.count,
            sha256: sha256Hex(data)
        )
    }

    static func backfillThreadLedgers(
        projectPath: String,
        limit: Int = .max,
        force: Bool = false,
        fileManager: FileManager = .default
    ) throws -> CodexChatLedgerBackfillSummary {
        guard limit > 0 else {
            throw NSError(
                domain: "CodexChatCLI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Backfill limit must be a positive integer"]
            )
        }

        let normalizedProjectPath = normalizeProjectPath(projectPath)
        let markerDirectory = ledgerBackfillMarkerDirectory(projectPath: normalizedProjectPath)
        try fileManager.createDirectory(at: markerDirectory, withIntermediateDirectories: true)

        let threadIDs = try discoverArchivedThreadIDs(projectPath: normalizedProjectPath, fileManager: fileManager)
        var exportedCount = 0
        var skippedCount = 0
        var threadResults: [CodexChatLedgerBackfillThreadResult] = []
        threadResults.reserveCapacity(threadIDs.count)

        for threadID in threadIDs {
            let markerURL = ledgerBackfillMarkerURL(projectPath: normalizedProjectPath, threadID: threadID)

            if !force, fileManager.fileExists(atPath: markerURL.path) {
                if let marker = readBackfillMarker(from: markerURL),
                   marker.threadID == threadID,
                   fileManager.fileExists(atPath: marker.ledgerPath)
                {
                    skippedCount += 1
                    threadResults.append(
                        CodexChatLedgerBackfillThreadResult(
                            threadID: threadID,
                            status: "skipped",
                            ledgerPath: marker.ledgerPath,
                            markerPath: markerURL.path,
                            entryCount: marker.entryCount,
                            sha256: marker.sha256
                        )
                    )
                    continue
                }
            }

            let exportSummary = try exportThreadLedger(
                projectPath: normalizedProjectPath,
                threadID: threadID,
                limit: limit,
                outputURL: nil,
                fileManager: fileManager
            )

            let marker = CodexChatLedgerBackfillMarker(
                schemaVersion: 1,
                generatedAt: Date(),
                projectPath: normalizedProjectPath,
                threadID: threadID,
                ledgerPath: exportSummary.outputPath,
                entryCount: exportSummary.entryCount,
                sha256: exportSummary.sha256
            )
            try writeBackfillMarker(marker, to: markerURL)

            exportedCount += 1
            threadResults.append(
                CodexChatLedgerBackfillThreadResult(
                    threadID: threadID,
                    status: "exported",
                    ledgerPath: exportSummary.outputPath,
                    markerPath: markerURL.path,
                    entryCount: exportSummary.entryCount,
                    sha256: exportSummary.sha256
                )
            )
        }

        return CodexChatLedgerBackfillSummary(
            projectPath: normalizedProjectPath,
            markerDirectoryPath: markerDirectory.path,
            scannedThreadCount: threadIDs.count,
            exportedThreadCount: exportedCount,
            skippedThreadCount: skippedCount,
            threads: threadResults
        )
    }

    static func validateRuntimePolicyDocument(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> CodexChatRuntimePolicyValidationReport {
        let path = url.standardizedFileURL.path
        guard fileManager.fileExists(atPath: path) else {
            return CodexChatRuntimePolicyValidationReport(
                filePath: path,
                isValid: false,
                issues: [CodexChatRuntimePolicyIssue(severity: "error", message: "Policy file not found")],
                document: nil
            )
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document: CodexChatRuntimePolicyDocument
        do {
            document = try decoder.decode(CodexChatRuntimePolicyDocument.self, from: data)
        } catch {
            return CodexChatRuntimePolicyValidationReport(
                filePath: path,
                isValid: false,
                issues: [CodexChatRuntimePolicyIssue(severity: "error", message: "Invalid JSON payload: \(error.localizedDescription)")],
                document: nil
            )
        }

        var issues: [CodexChatRuntimePolicyIssue] = []

        if document.version != 1 {
            issues.append(CodexChatRuntimePolicyIssue(severity: "error", message: "Unsupported policy version: \(document.version)"))
        }

        let allowedApprovalPolicies: Set<String> = ["untrusted", "on-request", "never"]
        if !allowedApprovalPolicies.contains(document.defaultApprovalPolicy) {
            issues.append(
                CodexChatRuntimePolicyIssue(
                    severity: "error",
                    message: "defaultApprovalPolicy must be one of: untrusted, on-request, never"
                )
            )
        }

        let allowedSandboxModes: Set<String> = ["read-only", "workspace-write", "danger-full-access"]
        if !allowedSandboxModes.contains(document.defaultSandboxMode) {
            issues.append(
                CodexChatRuntimePolicyIssue(
                    severity: "error",
                    message: "defaultSandboxMode must be one of: read-only, workspace-write, danger-full-access"
                )
            )
        }

        if document.defaultApprovalPolicy == "never", !document.allowNeverApproval {
            issues.append(
                CodexChatRuntimePolicyIssue(
                    severity: "error",
                    message: "defaultApprovalPolicy=never requires allowNeverApproval=true"
                )
            )
        }

        if document.defaultSandboxMode == "danger-full-access", !document.allowDangerFullAccess {
            issues.append(
                CodexChatRuntimePolicyIssue(
                    severity: "error",
                    message: "defaultSandboxMode=danger-full-access requires allowDangerFullAccess=true"
                )
            )
        }

        if document.allowDangerFullAccess, !document.allowNeverApproval {
            issues.append(
                CodexChatRuntimePolicyIssue(
                    severity: "warning",
                    message: "Danger full access is enabled while never-approval is disabled; verify escalation UX"
                )
            )
        }

        let hasErrors = issues.contains(where: { $0.severity == "error" })
        return CodexChatRuntimePolicyValidationReport(
            filePath: path,
            isValid: !hasErrors,
            issues: issues,
            document: document
        )
    }

    static func defaultRuntimePolicyURL(fileManager: FileManager = .default) -> URL? {
        guard let repoRoot = discoverRepositoryRoot(fileManager: fileManager) else {
            return nil
        }

        return repoRoot
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("runtime-policy", isDirectory: true)
            .appendingPathComponent("default-policy.json", isDirectory: false)
    }
}

private extension CodexChatBootstrap {
    static func normalizeProjectPath(_ projectPath: String) -> String {
        let expanded = NSString(string: projectPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    static func makeLedgerEntries(turns: [CodexChatReplayTurn]) -> [CodexChatThreadLedgerEntry] {
        var entries: [CodexChatThreadLedgerEntry] = []
        entries.reserveCapacity(turns.count * 3)

        var sequence = 1
        for turn in turns {
            entries.append(
                CodexChatThreadLedgerEntry(
                    sequence: sequence,
                    turnID: turn.turnID,
                    timestamp: turn.timestamp,
                    kind: "user_message",
                    status: turn.status,
                    method: nil,
                    title: nil,
                    text: turn.userText
                )
            )
            sequence += 1

            entries.append(
                CodexChatThreadLedgerEntry(
                    sequence: sequence,
                    turnID: turn.turnID,
                    timestamp: turn.timestamp,
                    kind: "assistant_message",
                    status: turn.status,
                    method: nil,
                    title: nil,
                    text: turn.assistantText
                )
            )
            sequence += 1

            for action in turn.actions {
                entries.append(
                    CodexChatThreadLedgerEntry(
                        sequence: sequence,
                        turnID: turn.turnID,
                        timestamp: action.createdAt,
                        kind: "action_card",
                        status: turn.status,
                        method: action.method,
                        title: action.title,
                        text: action.detail
                    )
                )
                sequence += 1
            }
        }

        return entries
    }

    static func defaultLedgerURL(projectPath: String, threadID: UUID) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent("\(threadID.uuidString).ledger.json", isDirectory: false)
    }

    static func ledgerBackfillMarkerDirectory(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent(".ledger-backfill", isDirectory: true)
    }

    static func ledgerBackfillMarkerURL(projectPath: String, threadID: UUID) -> URL {
        ledgerBackfillMarkerDirectory(projectPath: projectPath)
            .appendingPathComponent("\(threadID.uuidString).json", isDirectory: false)
    }

    static func discoverArchivedThreadIDs(projectPath: String, fileManager: FileManager) throws -> [UUID] {
        let threadsDirectory = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)

        guard fileManager.fileExists(atPath: threadsDirectory.path) else {
            return []
        }

        let entries = try fileManager.contentsOfDirectory(at: threadsDirectory, includingPropertiesForKeys: nil)
        let threadIDs = entries.compactMap { entry -> UUID? in
            guard entry.pathExtension.lowercased() == "md" else {
                return nil
            }

            let candidate = entry.deletingPathExtension().lastPathComponent
            return UUID(uuidString: candidate)
        }

        return threadIDs.sorted { $0.uuidString < $1.uuidString }
    }

    static func writeBackfillMarker(
        _ marker: CodexChatLedgerBackfillMarker,
        to destination: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(marker)
        try data.write(to: destination, options: .atomic)
    }

    static func readBackfillMarker(from source: URL) -> CodexChatLedgerBackfillMarker? {
        guard let data = try? Data(contentsOf: source) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexChatLedgerBackfillMarker.self, from: data)
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func discoverRepositoryRoot(fileManager: FileManager) -> URL? {
        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true).standardizedFileURL
        let markerPath = "apps/CodexChatApp/Package.swift"

        while true {
            if fileManager.fileExists(atPath: cursor.appendingPathComponent(markerPath).path) {
                return cursor
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                return nil
            }
            cursor = parent
        }
    }
}
