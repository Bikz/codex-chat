import CodexChatCore
import CodexKit
import CodexMemory
import Foundation

extension AppModel {
    func persistCompletedTurn(context: ActiveTurnContext) async {
        let assistantText = context.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)

        let summary = ArchivedTurnSummary(
            timestamp: context.startedAt,
            userText: context.userText,
            assistantText: assistantText,
            actions: context.actions
        )

        do {
            let archiveURL = try ChatArchiveStore.appendTurn(
                projectPath: context.projectPath,
                threadID: context.localThreadID,
                turn: summary
            )
            projectStatusMessage = "Archived chat turn to \(archiveURL.lastPathComponent)."

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
        } catch {
            appendLog(.error, "Failed to archive turn: \(error.localizedDescription)")
        }

        await appendMemorySummaryIfEnabled(context: context, assistantText: assistantText)
    }

    func processModChangesIfNeeded(context: ActiveTurnContext) {
        guard pendingModReview == nil else { return }

        let changes = reviewChangesByThreadID[context.localThreadID] ?? []
        guard !changes.isEmpty else {
            discardModSnapshotIfPresent()
            return
        }

        let snapshot = activeModSnapshot
        let projectRootPath = snapshot?.projectRootPath ?? Self.projectModsRootPath(projectPath: context.projectPath)
        let globalRootPath = snapshot?.globalRootPath ?? (try? Self.globalModsRootPath())

        let modChanges = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: context.projectPath,
            globalRootPath: globalRootPath,
            projectRootPath: projectRootPath
        )

        guard !modChanges.isEmpty else {
            discardModSnapshotIfPresent()
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

    func discardModSnapshotIfPresent() {
        guard let snapshot = activeModSnapshot else { return }
        ModEditSafety.discard(snapshot: snapshot)
        activeModSnapshot = nil
    }

    private func appendMemorySummaryIfEnabled(context: ActiveTurnContext, assistantText: String) async {
        guard let projectRepository else { return }

        do {
            let project = try await projectRepository.getProject(id: context.projectID) ?? selectedProject
            guard let project, project.memoryWriteMode != .off else {
                return
            }

            let store = ProjectMemoryStore(projectPath: context.projectPath)
            try await store.ensureStructure()
            let markdown = MemoryAutoSummary.markdown(
                timestamp: context.startedAt,
                threadID: context.localThreadID,
                userText: context.userText,
                assistantText: assistantText,
                actions: context.actions,
                mode: project.memoryWriteMode
            )

            try await store.appendToSummaryLog(markdown: markdown)
            appendLog(.info, "Appended memory summary for thread \(context.localThreadID.uuidString)")
        } catch {
            appendLog(.error, "Failed to append memory summary: \(error.localizedDescription)")
        }
    }
}
