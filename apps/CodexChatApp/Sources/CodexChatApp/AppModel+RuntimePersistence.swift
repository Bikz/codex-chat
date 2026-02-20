import CodexChatCore
import CodexKit
import CodexMemory
import Foundation

extension AppModel {
    func persistCompletedTurn(context: ActiveTurnContext, completion: RuntimeTurnCompletion) async {
        let span = await PerformanceTracer.shared.begin(
            name: "thread.persistCompletedTurn",
            metadata: ["threadID": context.localThreadID.uuidString]
        )
        defer {
            Task {
                await PerformanceTracer.shared.end(span)
            }
        }

        let assistantText = context.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStatus = completion.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let turnFailed = completion.errorMessage != nil
            || normalizedStatus.contains("fail")
            || normalizedStatus.contains("error")
            || normalizedStatus.contains("cancel")
        let turnStatus: ChatArchiveTurnStatus = turnFailed ? .failed : .completed

        var persistedActions = context.actions
        if let errorMessage = completion.errorMessage, !errorMessage.isEmpty {
            persistedActions.append(
                ActionCard(
                    threadID: context.localThreadID,
                    method: "turn/error",
                    title: "Turn error",
                    detail: errorMessage,
                    createdAt: Date()
                )
            )
        }

        var isThreadArchived = false
        if let threadRepository,
           let thread = try? await threadRepository.getThread(id: context.localThreadID)
        {
            isThreadArchived = thread.archivedAt != nil
        }

        let summary = ArchivedTurnSummary(
            turnID: context.localTurnID,
            timestamp: context.startedAt,
            status: turnStatus,
            userText: context.userText,
            assistantText: assistantText,
            actions: persistedActions
        )

        do {
            let archiveURL = try await TurnPersistenceWorker.shared.persistArchive(
                projectPath: context.projectPath,
                threadID: context.localThreadID,
                summary: summary,
                turnStatus: turnStatus
            )
            projectStatusMessage = "Archived chat turn to \(archiveURL.lastPathComponent)."
            emitExtensionEvent(
                .transcriptPersisted,
                projectID: context.projectID,
                projectPath: context.projectPath,
                threadID: context.localThreadID,
                turnID: context.localTurnID.uuidString,
                turnStatus: turnStatus.rawValue,
                payload: [
                    "archivePath": archiveURL.path,
                    "status": turnStatus.rawValue,
                ]
            )

            guard !isThreadArchived else {
                appendLog(.debug, "Skipped indexing archived thread \(context.localThreadID.uuidString)")
                return
            }

            _ = try await threadRepository?.touchThread(id: context.localThreadID)

            try await chatSearchRepository?.indexMessageExcerpt(
                threadID: context.localThreadID,
                projectID: context.projectID,
                text: context.userText
            )

            if !assistantText.isEmpty {
                try await chatSearchRepository?.indexMessageExcerpt(
                    threadID: context.localThreadID,
                    projectID: context.projectID,
                    text: assistantText
                )
            }

            if !turnFailed {
                await applyInitialThreadTitleIfNeeded(
                    threadID: context.localThreadID,
                    projectID: context.projectID,
                    userText: context.userText,
                    assistantText: assistantText
                )
            }
        } catch {
            appendLog(.error, "Failed to archive turn: \(error.localizedDescription)")
        }

        guard !isThreadArchived else {
            return
        }
        await appendMemorySummaryIfEnabled(context: context, assistantText: assistantText)
    }

    func applyInitialThreadTitleIfNeeded(
        threadID: UUID,
        projectID: UUID,
        userText: String,
        assistantText: String
    ) async {
        guard pendingFirstTurnTitleThreadIDs.contains(threadID) else {
            return
        }
        pendingFirstTurnTitleThreadIDs.remove(threadID)

        guard let threadRepository else {
            return
        }

        let fallbackTitle = Self.autoTitleFromFirstTurn(userText: userText, assistantText: assistantText)
        guard !fallbackTitle.isEmpty else {
            return
        }

        await persistThreadTitle(
            threadRepository: threadRepository,
            threadID: threadID,
            projectID: projectID,
            title: fallbackTitle
        )

        let selectedModelID = {
            let trimmed = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let reasoningModelID = selectedModelID ?? runtimeDefaultModelID
        let clampedReasoning = clampedReasoningLevel(.low, forModelID: reasoningModelID)
        let reasoningEffort = clampedReasoning == .none ? nil : clampedReasoning.rawValue

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            guard let generatedTitle = await ChatTitleGenerator.generateTitleWithEphemeralRuntime(
                userText: userText,
                model: selectedModelID,
                reasoningEffort: reasoningEffort
            ) else {
                return
            }

            await applyGeneratedThreadTitleIfEligible(
                threadID: threadID,
                projectID: projectID,
                generatedTitle: generatedTitle,
                fallbackTitle: fallbackTitle
            )
        }
    }

    private func applyGeneratedThreadTitleIfEligible(
        threadID: UUID,
        projectID: UUID,
        generatedTitle: String,
        fallbackTitle: String
    ) async {
        guard let threadRepository else {
            return
        }

        let trimmedGenerated = generatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGenerated.isEmpty,
              trimmedGenerated.caseInsensitiveCompare(fallbackTitle) != .orderedSame
        else {
            return
        }

        do {
            guard let existingThread = try await threadRepository.getThread(id: threadID) else {
                return
            }

            let existingTitle = existingThread.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldReplace = existingTitle.caseInsensitiveCompare(fallbackTitle) == .orderedSame
                || existingTitle.caseInsensitiveCompare("New chat") == .orderedSame
            guard shouldReplace else {
                return
            }
        } catch {
            appendLog(.debug, "Skipping generated thread title update: \(error.localizedDescription)")
            return
        }

        await persistThreadTitle(
            threadRepository: threadRepository,
            threadID: threadID,
            projectID: projectID,
            title: trimmedGenerated
        )
    }

    private func persistThreadTitle(
        threadRepository: any ThreadRepository,
        threadID: UUID,
        projectID: UUID,
        title: String
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        do {
            let updated = try await threadRepository.updateThreadTitle(id: threadID, title: trimmedTitle)
            try await chatSearchRepository?.indexThreadTitle(
                threadID: threadID,
                projectID: projectID,
                title: updated.title
            )

            if generalProject?.id == projectID {
                try await refreshGeneralThreads(generalProjectID: projectID)
            }
            if selectedProjectID == projectID {
                try await refreshThreads()
            }
        } catch {
            appendLog(.error, "Failed to auto-title thread: \(error.localizedDescription)")
        }
    }

    nonisolated static func autoTitleFromFirstTurn(userText: String, assistantText: String) -> String {
        for source in [assistantText, userText] {
            if let candidate = firstTitleCandidate(from: source) {
                return candidate
            }
        }
        return "New chat"
    }

    private nonisolated static func firstTitleCandidate(from source: String) -> String? {
        let strippedCode = source.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: " ",
            options: .regularExpression
        )
        let normalized = strippedCode
            .replacingOccurrences(of: "\\[(.*?)\\]\\((.*?)\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        let cleanedPreamble = normalized.replacingOccurrences(
            of: "^(sure|certainly|absolutely|okay|ok|here(?:'s| is)|i(?:'ll| will)|let(?:'s| us))[,\\-:\\s]+",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let cleanedMarkdown = cleanedPreamble
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^[-*\\d\\.)\\s]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        guard cleanedMarkdown.count >= 3 else { return nil }

        let maxLength = 52
        let clipped: String
        if cleanedMarkdown.count <= maxLength {
            clipped = cleanedMarkdown
        } else {
            let prefix = String(cleanedMarkdown.prefix(maxLength))
            clipped = prefix.replacingOccurrences(of: "\\s+\\S*$", with: "", options: .regularExpression)
        }

        let trimmed = clipped
            .replacingOccurrences(of: "[\\.:;!?,]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let first = trimmed.prefix(1).uppercased()
        let remainder = trimmed.dropFirst()
        return first + remainder
    }

    func processModChangesIfNeeded(context: ActiveTurnContext) {
        guard pendingModReview == nil else { return }

        let changes = reviewChangesByThreadID[context.localThreadID] ?? []
        guard !changes.isEmpty else {
            discardModSnapshotIfPresent(threadID: context.localThreadID)
            return
        }

        let snapshot = activeModSnapshotByThreadID[context.localThreadID]
        let projectRootPath = snapshot?.projectRootPath ?? Self.projectModsRootPath(projectPath: context.projectPath)
        let globalRootPath = snapshot?.globalRootPath ?? (try? Self.globalModsRootPath())

        let modChanges = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: context.projectPath,
            globalRootPath: globalRootPath,
            projectRootPath: projectRootPath
        )

        guard !modChanges.isEmpty else {
            discardModSnapshotIfPresent(threadID: context.localThreadID)
            return
        }

        pendingModReview = PendingModReview(
            id: UUID(),
            threadID: context.localThreadID,
            changes: modChanges,
            reason: "Codex proposed edits to mod files. Review is required before continuing.",
            canRevert: snapshot != nil
        )

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: context.localThreadID,
                    method: "mods/reviewRequired",
                    title: "Mod changes require approval",
                    detail: "Review and accept or revert \(modChanges.count) mod-related change(s)."
                )
            ),
            to: context.localThreadID
        )
    }

    func discardModSnapshotIfPresent(threadID: UUID? = nil) {
        if let threadID {
            guard let snapshot = activeModSnapshotByThreadID.removeValue(forKey: threadID) else { return }
            ModEditSafety.discard(snapshot: snapshot)
            return
        }

        let snapshots = activeModSnapshotByThreadID.values
        activeModSnapshotByThreadID.removeAll(keepingCapacity: false)
        for snapshot in snapshots {
            ModEditSafety.discard(snapshot: snapshot)
        }
    }

    private func appendMemorySummaryIfEnabled(context: ActiveTurnContext, assistantText: String) async {
        guard context.memoryWriteMode != .off else {
            return
        }

        do {
            let store = ProjectMemoryStore(projectPath: context.projectPath)
            try await store.ensureStructure()
            let markdown = MemoryAutoSummary.markdown(
                timestamp: context.startedAt,
                threadID: context.localThreadID,
                userText: context.userText,
                assistantText: assistantText,
                actions: context.actions,
                mode: context.memoryWriteMode
            )

            try await store.appendToSummaryLog(markdown: markdown)
            appendLog(.info, "Appended memory summary for thread \(context.localThreadID.uuidString)")
        } catch {
            appendLog(.error, "Failed to append memory summary: \(error.localizedDescription)")
        }
    }
}
