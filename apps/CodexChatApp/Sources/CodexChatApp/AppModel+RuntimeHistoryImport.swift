import CodexChatCore
import CodexKit
import Foundation

private func runtimeImportObject(_ value: JSONValue?) -> [String: JSONValue]? {
    guard let value, case let .object(object) = value else {
        return nil
    }
    return object
}

private func runtimeImportArray(_ value: JSONValue?) -> [JSONValue]? {
    guard let value, case let .array(array) = value else {
        return nil
    }
    return array
}

private func runtimeImportString(_ value: JSONValue?) -> String? {
    guard let value, case let .string(string) = value else {
        return nil
    }
    return string
}

private func runtimeImportBool(_ value: JSONValue?) -> Bool? {
    guard let value, case let .bool(bool) = value else {
        return nil
    }
    return bool
}

private func runtimeImportInt(_ value: JSONValue?) -> Int? {
    guard let value else {
        return nil
    }
    if case let .number(number) = value {
        let rounded = number.rounded(.towardZero)
        guard rounded == number else {
            return nil
        }
        return Int(rounded)
    }
    if case let .string(string) = value {
        return Int(string)
    }
    return nil
}

private func runtimeImportValue(at keyPath: [String], in root: JSONValue?) -> JSONValue? {
    guard var current = root else {
        return nil
    }

    for key in keyPath {
        guard case let .object(object) = current,
              let next = object[key]
        else {
            return nil
        }
        current = next
    }

    return current
}

private func runtimeImportNormalizedText(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func runtimeImportDate(from value: JSONValue?) -> Date? {
    if let intValue = runtimeImportInt(value) {
        return Date(timeIntervalSince1970: TimeInterval(intValue))
    }
    if let stringValue = runtimeImportString(value),
       let timeInterval = TimeInterval(stringValue)
    {
        return Date(timeIntervalSince1970: timeInterval)
    }
    return nil
}

private func runtimeImportMetadataDetail(cwd: String?, source: String?) -> String? {
    var parts: [String] = []
    if let cwd, !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        parts.append("Workspace: \(cwd)")
    }
    if let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        parts.append("Source: \(source)")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

private func runtimeImportExtractText(from value: JSONValue) -> String {
    switch value {
    case let .string(text):
        return text
    case let .array(elements):
        return elements
            .map(runtimeImportExtractText(from:))
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    case let .object(object):
        if let text = runtimeImportString(object["text"]) {
            return text
        }
        if let markdown = runtimeImportString(object["markdown"]) {
            return markdown
        }
        if let nested = object["value"] {
            return runtimeImportExtractText(from: nested)
        }
        if let nested = object["content"] {
            return runtimeImportExtractText(from: nested)
        }
        if let title = runtimeImportString(object["title"]) {
            return title
        }
        return ""
    case .number, .bool, .null:
        return ""
    }
}

struct RuntimeHistoryThreadSummary: Hashable, Sendable {
    let runtimeThreadID: String
    let title: String
    let preview: String
    let createdAt: Date?
    let updatedAt: Date?
    let cwd: String?
    let source: String?
}

struct ImportedRuntimeHistoryThread: Sendable {
    struct Turn: Sendable {
        struct ActionDescriptor: Sendable {
            let method: String
            let title: String
            let detail: String
            let createdAt: Date
        }

        let timestamp: Date
        let userText: String
        let assistantText: String
        let actions: [ActionDescriptor]
    }

    let title: String
    let preview: String
    let createdAt: Date?
    let updatedAt: Date?
    let turns: [Turn]
}

enum RuntimeHistoryImportParser {
    static func threadSummaries(from value: JSONValue) -> [RuntimeHistoryThreadSummary] {
        let objects = runtimeImportArray(runtimeImportValue(at: ["data"], in: value))
            ?? runtimeImportArray(runtimeImportValue(at: ["threads"], in: value))
            ?? runtimeImportArray(runtimeImportValue(at: ["items"], in: value))
            ?? []

        return objects.compactMap { element in
            guard let object = runtimeImportObject(element),
                  let runtimeThreadID = runtimeImportString(object["id"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !runtimeThreadID.isEmpty
            else {
                return nil
            }

            if runtimeImportBool(object["ephemeral"]) == true {
                return nil
            }

            let preview = runtimeImportNormalizedText(
                runtimeImportString(object["preview"])
                    ?? runtimeImportString(object["summary"])
                    ?? ""
            )
            let title = runtimeImportNormalizedText(
                runtimeImportString(object["name"])
                    ?? runtimeImportString(object["title"])
                    ?? preview
            )

            return RuntimeHistoryThreadSummary(
                runtimeThreadID: runtimeThreadID,
                title: title.isEmpty ? "Imported conversation" : title,
                preview: preview,
                createdAt: runtimeImportDate(from: object["createdAt"]),
                updatedAt: runtimeImportDate(from: object["updatedAt"]),
                cwd: runtimeImportString(object["cwd"]),
                source: runtimeImportString(object["source"])
            )
        }
    }

    static func importedThread(
        from value: JSONValue,
        fallback: RuntimeHistoryThreadSummary
    ) -> ImportedRuntimeHistoryThread {
        let object = runtimeImportObject(runtimeImportValue(at: ["thread"], in: value))
            ?? runtimeImportObject(value)
            ?? [:]
        let preview = runtimeImportNormalizedText(
            runtimeImportString(object["preview"]) ?? fallback.preview
        )
        let title = runtimeImportNormalizedText(
            runtimeImportString(object["name"])
                ?? runtimeImportString(object["title"])
                ?? fallback.title
        )
        let createdAt = runtimeImportDate(from: object["createdAt"]) ?? fallback.createdAt
        let updatedAt = runtimeImportDate(from: object["updatedAt"]) ?? fallback.updatedAt
        let metadataDetail = runtimeImportMetadataDetail(
            cwd: runtimeImportString(object["cwd"]) ?? fallback.cwd,
            source: runtimeImportString(object["source"]) ?? fallback.source
        )

        let turns = (runtimeImportArray(object["turns"]) ?? []).enumerated().compactMap { index, rawTurn in
            importedTurn(
                from: rawTurn,
                threadCreatedAt: createdAt,
                fallbackPreview: preview,
                fallbackMetadataDetail: index == 0 ? metadataDetail : nil,
                index: index
            )
        }

        return ImportedRuntimeHistoryThread(
            title: title.isEmpty ? "Imported conversation" : title,
            preview: preview,
            createdAt: createdAt,
            updatedAt: updatedAt,
            turns: turns
        )
    }

    static func sort(lhs: RuntimeHistoryThreadSummary, rhs: RuntimeHistoryThreadSummary) -> Bool {
        let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
        let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.runtimeThreadID < rhs.runtimeThreadID
    }

    private static func importedTurn(
        from value: JSONValue,
        threadCreatedAt: Date?,
        fallbackPreview: String,
        fallbackMetadataDetail: String?,
        index: Int
    ) -> ImportedRuntimeHistoryThread.Turn? {
        guard let object = runtimeImportObject(value) else {
            return nil
        }

        let items = runtimeImportArray(object["items"]) ?? []
        var userFragments: [String] = []
        var assistantFragments: [String] = []

        for item in items {
            guard let itemObject = runtimeImportObject(item) else { continue }
            let type = (runtimeImportString(itemObject["type"]) ?? "").lowercased()
            let text = runtimeImportNormalizedText(
                runtimeImportExtractText(from: itemObject["content"] ?? item)
            )
            guard !text.isEmpty else { continue }

            if type.contains("user") {
                userFragments.append(text)
            } else if type.contains("assistant") || type.contains("agent") {
                assistantFragments.append(text)
            }
        }

        let userText = userFragments.joined(separator: "\n\n")
        let assistantText = assistantFragments.joined(separator: "\n\n")
        let resolvedUserText = !userText.isEmpty ? userText : (index == 0 ? fallbackPreview : "")
        guard !resolvedUserText.isEmpty || !assistantText.isEmpty else {
            return nil
        }

        var actions: [ImportedRuntimeHistoryThread.Turn.ActionDescriptor] = []
        if let fallbackMetadataDetail {
            actions.append(
                .init(
                    method: "thread/import",
                    title: "Imported from Codex",
                    detail: fallbackMetadataDetail,
                    createdAt: Date()
                )
            )
        }

        return ImportedRuntimeHistoryThread.Turn(
            timestamp: runtimeImportDate(from: object["updatedAt"])
                ?? runtimeImportDate(from: object["createdAt"])
                ?? threadCreatedAt
                ?? Date(),
            userText: resolvedUserText,
            assistantText: assistantText,
            actions: actions
        )
    }
}

private enum RuntimeHistoryImportPreference: String {
    case imported
    case skipped
    case empty
}

enum RuntimeHistoryImportError: LocalizedError {
    case projectExistsWithoutMarker(String)
    case noImportableThreadsWereParsed

    var errorDescription: String? {
        switch self {
        case let .projectExistsWithoutMarker(path):
            "A project already exists at \(path) without a CodexChat import marker."
        case .noImportableThreadsWereParsed:
            "CodexChat found Codex history, but couldn't parse any importable conversations."
        }
    }
}

struct RuntimeHistoryImportProjectMarker: Codable, Sendable {
    static let fileName = ".codexchat-runtime-history-import.json"

    let schemaVersion: Int
    let createdAt: String
}

struct RuntimeHistoryImportManifest: Codable, Sendable {
    static let fileName = ".codexchat-runtime-history-manifest.json"

    let schemaVersion: Int
    let createdAt: String
    var updatedAt: String
    var importedRuntimeThreadIDs: [String]
}

enum RuntimeHistoryImportStore {
    static func projectMarkerURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(RuntimeHistoryImportProjectMarker.fileName, isDirectory: false)
    }

    static func manifestURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(RuntimeHistoryImportManifest.fileName, isDirectory: false)
    }

    static func isOwnedImportedProject(
        projectPath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: projectMarkerURL(projectPath: projectPath).path)
    }

    static func writeProjectMarker(
        projectPath: String,
        fileManager: FileManager = .default
    ) throws {
        let marker = RuntimeHistoryImportProjectMarker(
            schemaVersion: 1,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let data = try JSONEncoder().encode(marker)
        try fileManager.createDirectory(at: URL(fileURLWithPath: projectPath, isDirectory: true), withIntermediateDirectories: true)
        try data.write(to: projectMarkerURL(projectPath: projectPath), options: [.atomic])
    }

    static func readManifest(
        projectPath: String,
        fileManager: FileManager = .default
    ) throws -> RuntimeHistoryImportManifest? {
        let url = manifestURL(projectPath: projectPath)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuntimeHistoryImportManifest.self, from: data)
    }

    static func writeManifest(
        _ manifest: RuntimeHistoryImportManifest,
        projectPath: String,
        fileManager: FileManager = .default
    ) throws {
        let data = try JSONEncoder().encode(manifest)
        try fileManager.createDirectory(at: URL(fileURLWithPath: projectPath, isDirectory: true), withIntermediateDirectories: true)
        try data.write(to: manifestURL(projectPath: projectPath), options: [.atomic])
    }

    static func makeEmptyManifest() -> RuntimeHistoryImportManifest {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return RuntimeHistoryImportManifest(
            schemaVersion: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            importedRuntimeThreadIDs: []
        )
    }

    static func registerImportedRuntimeThreadID(
        _ runtimeThreadID: String,
        projectPath: String,
        fileManager: FileManager = .default
    ) throws {
        var manifest = try readManifest(projectPath: projectPath, fileManager: fileManager) ?? makeEmptyManifest()
        guard !manifest.importedRuntimeThreadIDs.contains(runtimeThreadID) else {
            return
        }
        manifest.importedRuntimeThreadIDs.append(runtimeThreadID)
        manifest.importedRuntimeThreadIDs.sort()
        manifest.updatedAt = ISO8601DateFormatter().string(from: Date())
        try writeManifest(manifest, projectPath: projectPath, fileManager: fileManager)
    }

    static func importedRuntimeThreadIDs(
        projectPath: String,
        fileManager: FileManager = .default
    ) throws -> Set<String> {
        try Set(readManifest(projectPath: projectPath, fileManager: fileManager)?.importedRuntimeThreadIDs ?? [])
    }
}

extension AppModel {
    private static let importedRuntimeHistoryProjectName = "Imported from Codex"
    private static let runtimeHistoryImportWorkerID = RuntimePoolWorkerID(0)

    var shouldShowRuntimeHistoryImportCard: Bool {
        switch runtimeHistoryImportState {
        case .checking, .available, .importing, .failed:
            true
        case .idle:
            false
        }
    }

    var runtimeHistoryImportSubtitle: String {
        switch runtimeHistoryImportState {
        case .idle:
            return ""
        case .checking:
            return "Checking your shared Codex history..."
        case let .available(threadCount):
            let noun = threadCount == 1 ? "conversation" : "conversations"
            return "Found \(threadCount) existing Codex \(noun). Import them into a separate CodexChat project."
        case .importing:
            return "Copying existing Codex conversations into CodexChat..."
        case let .failed(message):
            return message
        }
    }

    var runtimeHistoryImportCaption: String {
        switch runtimeHistoryImportState {
        case .available:
            "This is a one-time copy. Imported chats stay in CodexChat and won't remain linked to the live Codex runtime store."
        case .failed:
            "You can keep going without importing. New CodexChat chats stay separate either way."
        default:
            ""
        }
    }

    func refreshRuntimeHistoryImportAvailabilityIfNeeded() async {
        guard onboardingMode == .active else {
            runtimeHistoryImportCandidates = []
            runtimeHistoryImportState = .idle
            return
        }

        guard let preferenceRepository else {
            return
        }

        do {
            if try await preferenceRepository.getPreference(key: .runtimeThreadImportV1) != nil {
                runtimeHistoryImportCandidates = []
                runtimeHistoryImportState = .idle
                return
            }
        } catch {
            appendLog(.debug, "Unable to read runtime history import preference: \(error.localizedDescription)")
        }

        guard runtimeStatus == .connected,
              runtimeIssue == nil,
              isSignedInForRuntime,
              let runtimePool
        else {
            runtimeHistoryImportCandidates = []
            runtimeHistoryImportState = .idle
            return
        }

        if case .importing = runtimeHistoryImportState {
            return
        }

        runtimeHistoryImportState = .checking

        do {
            let candidates = try await listImportableRuntimeHistoryThreads(runtimePool: runtimePool)
            runtimeHistoryImportCandidates = candidates

            if candidates.isEmpty {
                try? await preferenceRepository.setPreference(
                    key: .runtimeThreadImportV1,
                    value: RuntimeHistoryImportPreference.empty.rawValue
                )
                runtimeHistoryImportState = .idle
                completeOnboardingIfReady()
                return
            }

            runtimeHistoryImportState = .available(threadCount: candidates.count)
        } catch {
            runtimeHistoryImportCandidates = []
            runtimeHistoryImportState = .failed("We found your shared Codex account, but couldn't read old Codex conversations yet.")
            appendLog(.warning, "Runtime history import discovery failed: \(error.localizedDescription)")
        }
    }

    func importRuntimeHistory() {
        guard runtimeHistoryImportTask == nil else {
            return
        }

        runtimeHistoryImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { runtimeHistoryImportTask = nil }
            await performRuntimeHistoryImport()
        }
    }

    func skipRuntimeHistoryImport() {
        Task {
            guard let preferenceRepository else { return }
            runtimeHistoryImportCandidates = []
            runtimeHistoryImportState = .idle
            try? await preferenceRepository.setPreference(
                key: .runtimeThreadImportV1,
                value: RuntimeHistoryImportPreference.skipped.rawValue
            )
            completeOnboardingIfReady()
        }
    }

    private func performRuntimeHistoryImport() async {
        guard let runtimePool,
              let preferenceRepository,
              let projectRepository,
              let threadRepository
        else {
            runtimeHistoryImportState = .failed("Runtime history import is unavailable right now.")
            return
        }

        runtimeHistoryImportState = .importing

        do {
            let candidates = runtimeHistoryImportCandidates.isEmpty
                ? try await listImportableRuntimeHistoryThreads(runtimePool: runtimePool)
                : runtimeHistoryImportCandidates

            if candidates.isEmpty {
                try await preferenceRepository.setPreference(
                    key: .runtimeThreadImportV1,
                    value: RuntimeHistoryImportPreference.empty.rawValue
                )
                runtimeHistoryImportState = .idle
                completeOnboardingIfReady()
                return
            }

            let importedProject = try await ensureImportedRuntimeHistoryProject(projectRepository: projectRepository)
            var alreadyImportedRuntimeThreadIDs = try RuntimeHistoryImportStore.importedRuntimeThreadIDs(
                projectPath: importedProject.path
            )
            var importedThreadCount = 0

            for candidate in candidates.sorted(by: RuntimeHistoryImportParser.sort) {
                if alreadyImportedRuntimeThreadIDs.contains(candidate.runtimeThreadID) {
                    continue
                }

                guard let importedThread = try await loadImportedRuntimeHistoryThread(
                    runtimePool: runtimePool,
                    candidate: candidate
                ) else {
                    continue
                }

                let localThread = try await threadRepository.createThread(
                    projectID: importedProject.id,
                    title: importedThread.title
                )
                try await appendImportedTurns(importedThread, to: localThread, projectPath: importedProject.path)
                try RuntimeHistoryImportStore.registerImportedRuntimeThreadID(
                    candidate.runtimeThreadID,
                    projectPath: importedProject.path
                )
                alreadyImportedRuntimeThreadIDs.insert(candidate.runtimeThreadID)
                importedThreadCount += 1
            }

            if importedThreadCount == 0 {
                throw RuntimeHistoryImportError.noImportableThreadsWereParsed
            }

            try await preferenceRepository.setPreference(
                key: .runtimeThreadImportV1,
                value: RuntimeHistoryImportPreference.imported.rawValue
            )

            runtimeHistoryImportCandidates = []
            runtimeHistoryImportState = .idle
            try await refreshProjects()
            onboardingCompletionTask?.cancel()
            onboardingCompletionTask = nil
            onboardingMode = .inactive
            selectProject(importedProject.id)
            projectStatusMessage = importedThreadCount > 0
                ? "Imported \(importedThreadCount) Codex conversation(s) into \(Self.importedRuntimeHistoryProjectName)."
                : "No Codex conversations were imported."
            appendLog(.info, "Imported \(importedThreadCount) runtime conversation(s) into \(importedProject.path)")
        } catch {
            runtimeHistoryImportState = .failed("Couldn't import existing Codex conversations right now.")
            appendLog(.error, "Runtime history import failed: \(error.localizedDescription)")
        }
    }

    private func listImportableRuntimeHistoryThreads(
        runtimePool: RuntimePool
    ) async throws -> [RuntimeHistoryThreadSummary] {
        var cursor: String?
        var collected: [RuntimeHistoryThreadSummary] = []
        var seenIDs: Set<String> = []
        var seenCursors: Set<String> = []

        while true {
            let result = try await runtimePool.listThreads(cursor: cursor)
            let page = RuntimeHistoryImportParser.threadSummaries(from: result)
            for candidate in page where seenIDs.insert(candidate.runtimeThreadID).inserted {
                collected.append(candidate)
            }

            let nextCursor = runtimeImportString(runtimeImportValue(at: ["nextCursor"], in: result))
                ?? runtimeImportString(runtimeImportValue(at: ["cursor"], in: result))
            guard let nextCursor,
                  !nextCursor.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty,
                  nextCursor != cursor,
                  seenCursors.insert(nextCursor).inserted
            else {
                break
            }
            cursor = nextCursor
        }

        return collected
    }

    private func ensureImportedRuntimeHistoryProject(
        projectRepository: any ProjectRepository
    ) async throws -> ProjectRecord {
        try storagePaths.ensureRootStructure()
        let canonicalProjectURL = storagePaths.projectsURL
            .appendingPathComponent(Self.importedRuntimeHistoryProjectName, isDirectory: true)

        let knownProjects = try await (projects.isEmpty ? projectRepository.listProjects() : projects)
        if let ownedProject = knownProjects.first(where: {
            RuntimeHistoryImportStore.isOwnedImportedProject(projectPath: $0.path)
        }) {
            try await prepareProjectFolderStructure(projectPath: ownedProject.path)
            if try RuntimeHistoryImportStore.readManifest(projectPath: ownedProject.path) == nil {
                try RuntimeHistoryImportStore.writeManifest(
                    RuntimeHistoryImportStore.makeEmptyManifest(),
                    projectPath: ownedProject.path
                )
            }
            return ownedProject
        }

        if let existing = knownProjects.first(where: { $0.path == canonicalProjectURL.path }) {
            throw RuntimeHistoryImportError.projectExistsWithoutMarker(existing.path)
        }

        if let existing = try await projectRepository.getProject(path: canonicalProjectURL.path) {
            throw RuntimeHistoryImportError.projectExistsWithoutMarker(existing.path)
        }

        let importedProjectURL = storagePaths.uniqueProjectDirectoryURL(
            requestedName: Self.importedRuntimeHistoryProjectName
        )

        if let existing = knownProjects.first(where: { $0.path == importedProjectURL.path }) {
            try await prepareProjectFolderStructure(projectPath: existing.path)
            if !RuntimeHistoryImportStore.isOwnedImportedProject(projectPath: existing.path) {
                throw RuntimeHistoryImportError.projectExistsWithoutMarker(existing.path)
            }
            return existing
        }

        try FileManager.default.createDirectory(at: importedProjectURL, withIntermediateDirectories: true)
        let project = try await projectRepository.createProject(
            named: Self.importedRuntimeHistoryProjectName,
            path: importedProjectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        try await applyGlobalSafetyDefaultsToProjectIfNeeded(projectID: project.id)
        try await prepareProjectFolderStructure(projectPath: project.path)
        try RuntimeHistoryImportStore.writeProjectMarker(projectPath: project.path)
        try RuntimeHistoryImportStore.writeManifest(
            RuntimeHistoryImportStore.makeEmptyManifest(),
            projectPath: project.path
        )
        return project
    }

    private func loadImportedRuntimeHistoryThread(
        runtimePool: RuntimePool,
        candidate: RuntimeHistoryThreadSummary
    ) async throws -> ImportedRuntimeHistoryThread? {
        let scopedThreadID = RuntimePool.scope(
            id: candidate.runtimeThreadID,
            workerID: Self.runtimeHistoryImportWorkerID
        )
        let resumed = try await runtimePool.resumeThread(scopedThreadID: scopedThreadID)
        let imported = RuntimeHistoryImportParser.importedThread(from: resumed, fallback: candidate)

        if imported.turns.isEmpty,
           imported.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return nil
        }

        return imported
    }

    private func appendImportedTurns(
        _ importedThread: ImportedRuntimeHistoryThread,
        to localThread: ThreadRecord,
        projectPath: String
    ) async throws {
        let turns: [ImportedRuntimeHistoryThread.Turn] = if importedThread.turns.isEmpty {
            [
                ImportedRuntimeHistoryThread.Turn(
                    timestamp: importedThread.updatedAt ?? importedThread.createdAt ?? Date(),
                    userText: importedThread.preview,
                    assistantText: "",
                    actions: [
                        .init(
                            method: "thread/import",
                            title: "Imported from Codex",
                            detail: "CodexChat could only import the thread preview for this conversation.",
                            createdAt: Date()
                        ),
                    ]
                ),
            ]
        } else {
            importedThread.turns
        }

        for turn in turns {
            let actions = turn.actions.map { descriptor in
                ActionCard(
                    threadID: localThread.id,
                    method: descriptor.method,
                    title: descriptor.title,
                    detail: descriptor.detail,
                    createdAt: descriptor.createdAt
                )
            }
            _ = try ChatArchiveStore.appendTurn(
                projectPath: projectPath,
                threadID: localThread.id,
                turn: ArchivedTurnSummary(
                    timestamp: turn.timestamp,
                    userText: turn.userText,
                    assistantText: turn.assistantText,
                    actions: actions
                )
            )
        }
    }
}
