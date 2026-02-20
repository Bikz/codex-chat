import AppKit
import CodexChatCore
import CodexComputerActions
import CodexKit
import Foundation

extension AppModel {
    enum PermissionRecoveryTarget: Equatable {
        case automation
        case calendars
        case reminders
        case genericAutomation

        var deepLinkCandidates: [String] {
            switch self {
            case .automation:
                [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                    "x-apple.systempreferences:com.apple.preference.security",
                ]
            case .calendars:
                [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                    "x-apple.systempreferences:com.apple.preference.security",
                ]
            case .reminders:
                [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
                    "x-apple.systempreferences:com.apple.preference.security",
                ]
            case .genericAutomation:
                [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                    "x-apple.systempreferences:com.apple.preference.security",
                ]
            }
        }

        var title: String {
            switch self {
            case .automation:
                "Automation permission needed"
            case .calendars:
                "Calendar permission needed"
            case .reminders:
                "Reminders permission needed"
            case .genericAutomation:
                "Permissions needed to run this automation"
            }
        }

        var remediationSteps: [String] {
            switch self {
            case .automation:
                [
                    "Open System Settings > Privacy & Security > Automation.",
                    "Enable automation access for CodexChat.",
                    "If CodexChat is not listed yet, retry the action once in CodexChat to trigger a system permission request, then reopen this pane.",
                    "Retry the action in CodexChat.",
                ]
            case .calendars:
                [
                    "Open System Settings > Privacy & Security > Calendars.",
                    "Enable calendar access for CodexChat.",
                    "If CodexChat is not listed yet, retry the action once in CodexChat to trigger a system permission request, then reopen this pane.",
                    "Retry the action in CodexChat.",
                ]
            case .reminders:
                [
                    "Open System Settings > Privacy & Security > Reminders.",
                    "Enable reminders access for CodexChat.",
                    "If CodexChat is not listed yet, retry the action once in CodexChat to trigger a system permission request, then reopen this pane.",
                    "Retry the action in CodexChat.",
                ]
            case .genericAutomation:
                [
                    "Open System Settings > Privacy & Security and check relevant app permissions.",
                    "Enable CodexChat for Automation and any required data category (Calendars/Reminders).",
                    "If CodexChat is not listed yet, retry the action once in CodexChat to trigger a system permission request, then reopen this pane.",
                    "Retry the action in CodexChat.",
                ]
            }
        }
    }

    func runNativeComputerAction(
        actionID: String,
        arguments: [String: String],
        threadID: UUID,
        projectID: UUID
    ) async throws {
        guard areNativeComputerActionsEnabled else {
            throw ComputerActionError.unsupported(
                "Native computer actions are disabled by config (features.native_computer_actions = false)."
            )
        }

        permissionRecoveryNotice = nil
        syncApprovalPresentationState()

        guard let provider = computerActionRegistry.provider(for: actionID) else {
            throw ComputerActionError.unsupported("Unknown computer action: \(actionID)")
        }

        let runContextID: String = {
            guard let candidate = arguments["runContextID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidate.isEmpty
            else {
                return UUID().uuidString
            }
            return candidate
        }()

        let request = ComputerActionRequest(
            runContextID: runContextID,
            arguments: arguments,
            artifactDirectoryPath: storagePaths.systemURL
                .appendingPathComponent("computer-actions", isDirectory: true)
                .path
        )

        let preview: ComputerActionPreviewArtifact
        do {
            preview = try await provider.preview(request: request)
        } catch {
            presentPermissionRecoveryNoticeIfNeeded(
                actionID: provider.actionID,
                arguments: request.arguments,
                error: error,
                threadID: threadID
            )
            throw error
        }
        let previewStatus: ComputerActionRunStatus = requiresExplicitConfirmation(for: provider)
            ? .awaitingConfirmation
            : .previewReady

        try await persistComputerActionRun(
            ComputerActionRunRecord(
                actionID: actionID,
                runContextID: runContextID,
                threadID: threadID,
                projectID: projectID,
                phase: .preview,
                status: previewStatus,
                previewArtifact: encodePreviewArtifact(preview),
                summary: preview.summary
            )
        )

        let previewState = PendingComputerActionPreview(
            threadID: threadID,
            projectID: projectID,
            request: request,
            artifact: preview,
            providerActionID: provider.actionID,
            providerDisplayName: provider.displayName,
            safetyLevel: provider.safetyLevel,
            requiresConfirmation: requiresExplicitConfirmation(for: provider)
        )

        if previewState.requiresConfirmation {
            pendingComputerActionPreview = previewState
            syncApprovalPresentationState()
            appendEntry(
                .actionCard(
                    ActionCard(
                        threadID: threadID,
                        method: "computer_action/preview",
                        title: "\(provider.displayName) preview ready",
                        detail: preview.detailsMarkdown
                    )
                ),
                to: threadID
            )
            computerActionStatusMessage = "Review the preview before confirming execution."
            return
        }

        try await executeComputerAction(previewState)
    }

    func confirmPendingComputerActionPreview() {
        guard let preview = pendingComputerActionPreview else {
            return
        }

        // Clear sheet state up front so execution (and any permission prompts) happen
        // after the preview UI starts dismissing.
        pendingComputerActionPreview = nil
        syncApprovalPresentationState()
        isComputerActionExecutionInProgress = true
        Task {
            defer { isComputerActionExecutionInProgress = false }
            await Task.yield()
            do {
                try await executeComputerAction(preview)
            } catch {
                computerActionStatusMessage = "Computer action failed: \(error.localizedDescription)"
                appendLog(.error, "Computer action execute failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelPendingComputerActionPreview() {
        pendingComputerActionPreview = nil
        syncApprovalPresentationState()
        computerActionStatusMessage = "Canceled computer action preview."
    }

    func undoLastDesktopCleanup() {
        guard let selectedThreadID else {
            computerActionStatusMessage = "Select a thread before undoing desktop cleanup."
            return
        }

        Task {
            do {
                guard let runRepo = computerActionRunRepository else {
                    throw CodexRuntimeError.invalidResponse("Computer action repository unavailable.")
                }

                let runs = try await runRepo.list(threadID: selectedThreadID)
                guard let latest = runs.first(where: {
                    $0.actionID == "desktop.cleanup" && $0.phase == .execute && $0.status == .executed
                }) else {
                    computerActionStatusMessage = "No completed desktop cleanup run found to undo."
                    return
                }

                guard let metadata = decodeDictionary(from: latest.previewArtifact),
                      let manifestPath = metadata["undoManifestPath"],
                      !manifestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    computerActionStatusMessage = "Undo manifest was not available for the last cleanup run."
                    return
                }

                let restoredCount = try computerActionRegistry.desktopCleanup.undoLastCleanup(manifestPath: manifestPath)
                let summary = restoredCount == 0
                    ? "Desktop cleanup undo completed with no restorable files."
                    : "Restored \(restoredCount) file(s) from the last desktop cleanup."

                try await persistComputerActionRun(
                    ComputerActionRunRecord(
                        actionID: "desktop.cleanup",
                        runContextID: latest.runContextID,
                        threadID: selectedThreadID,
                        projectID: latest.projectID,
                        phase: .undo,
                        status: .undone,
                        previewArtifact: latest.previewArtifact,
                        summary: summary
                    )
                )

                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: selectedThreadID,
                            method: "computer_action/undo",
                            title: "Desktop cleanup undone",
                            detail: summary
                        )
                    ),
                    to: selectedThreadID
                )
                computerActionStatusMessage = summary
            } catch {
                computerActionStatusMessage = "Undo failed: \(error.localizedDescription)"
                appendLog(.error, "Desktop cleanup undo failed: \(error.localizedDescription)")
            }
        }
    }

    private func executeComputerAction(_ previewState: PendingComputerActionPreview) async throws {
        guard let provider = computerActionRegistry.provider(for: previewState.providerActionID) else {
            throw ComputerActionError.unsupported("Unknown computer action: \(previewState.providerActionID)")
        }

        let isAllowed = try await ensureComputerActionPermission(
            actionID: provider.actionID,
            projectID: previewState.projectID,
            displayName: provider.displayName,
            safetyLevel: provider.safetyLevel
        )
        guard isAllowed else {
            try await persistComputerActionRun(
                ComputerActionRunRecord(
                    actionID: provider.actionID,
                    runContextID: previewState.request.runContextID,
                    threadID: previewState.threadID,
                    projectID: previewState.projectID,
                    phase: .execute,
                    status: .denied,
                    previewArtifact: encodePreviewArtifact(previewState.artifact),
                    summary: "User denied permission for \(provider.displayName)."
                )
            )
            throw ComputerActionError.permissionDenied("Permission denied for \(provider.displayName).")
        }

        let result: ComputerActionExecutionResult
        do {
            result = try await provider.execute(request: previewState.request, preview: previewState.artifact)
        } catch {
            presentPermissionRecoveryNoticeIfNeeded(
                actionID: provider.actionID,
                arguments: previewState.request.arguments,
                error: error,
                threadID: previewState.threadID
            )
            throw error
        }
        let resultMetadata = encodeDictionary(result.metadata)

        try await persistComputerActionRun(
            ComputerActionRunRecord(
                actionID: provider.actionID,
                runContextID: previewState.request.runContextID,
                threadID: previewState.threadID,
                projectID: previewState.projectID,
                phase: .execute,
                status: .executed,
                previewArtifact: resultMetadata,
                summary: result.summary
            )
        )

        let actionCard = ActionCard(
            threadID: previewState.threadID,
            method: "computer_action/execute",
            title: "\(provider.displayName) completed",
            detail: result.detailsMarkdown
        )
        await appendAndPersistComputerActionTranscriptTurn(
            actionCard: actionCard,
            previewState: previewState,
            provider: provider,
            result: result
        )

        computerActionStatusMessage = result.summary
        permissionRecoveryNotice = nil
        pendingComputerActionPreview = nil
        syncApprovalPresentationState()
    }

    private func appendAndPersistComputerActionTranscriptTurn(
        actionCard: ActionCard,
        previewState: PendingComputerActionPreview,
        provider: any ComputerActionProvider,
        result: ComputerActionExecutionResult
    ) async {
        let userText = computerActionUserPrompt(
            actionID: provider.actionID,
            displayName: provider.displayName,
            arguments: previewState.request.arguments
        )
        let assistantText = computerActionAssistantText(result: result)

        appendEntry(
            .message(
                ChatMessage(
                    threadId: previewState.threadID,
                    role: .user,
                    text: userText,
                    createdAt: actionCard.createdAt
                )
            ),
            to: previewState.threadID
        )
        appendEntry(.actionCard(actionCard), to: previewState.threadID)

        if !assistantText.isEmpty {
            appendEntry(
                .message(
                    ChatMessage(
                        threadId: previewState.threadID,
                        role: .assistant,
                        text: assistantText,
                        createdAt: actionCard.createdAt
                    )
                ),
                to: previewState.threadID
            )
        }

        await persistComputerActionTranscriptTurn(
            threadID: previewState.threadID,
            projectID: previewState.projectID,
            timestamp: actionCard.createdAt,
            userText: userText,
            assistantText: assistantText,
            actionCard: actionCard
        )

        await applyInitialThreadTitleIfNeeded(
            threadID: previewState.threadID,
            projectID: previewState.projectID,
            userText: userText,
            assistantText: assistantText
        )
    }

    private func computerActionUserPrompt(
        actionID: String,
        displayName: String,
        arguments: [String: String]
    ) -> String {
        switch actionID {
        case "calendar.today":
            if let queryText = arguments["queryText"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !queryText.isEmpty
            {
                return queryText
            }
            if let hoursRaw = arguments["rangeHours"],
               let hours = Int(hoursRaw),
               hours > 0
            {
                let dayOffset = Int(arguments["dayOffset"] ?? "0") ?? 0
                let anchor = arguments["anchor"]?.lowercased() ?? "dayStart"

                if anchor == "now", dayOffset == 0, hours < 24 {
                    return "Show my calendar for the next \(hours) hours."
                }

                if hours == 24 {
                    switch dayOffset {
                    case 1:
                        return "What's on my calendar tomorrow?"
                    case -1:
                        return "What was on my calendar yesterday?"
                    case 0:
                        return "What's on my calendar today?"
                    default:
                        return "Show my calendar for day offset \(dayOffset)."
                    }
                }
                return "Show my calendar for the next \(hours) hours."
            }
            return "What's on my calendar today?"
        case "calendar.create":
            if let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty
            {
                return "Create a calendar event titled \(title)."
            }
            return "Create a calendar event."
        case "calendar.update":
            if let eventID = arguments["eventID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !eventID.isEmpty
            {
                return "Update calendar event \(eventID)."
            }
            return "Update a calendar event."
        case "calendar.delete":
            if let eventID = arguments["eventID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !eventID.isEmpty
            {
                return "Delete calendar event \(eventID)."
            }
            return "Delete a calendar event."
        case "reminders.today":
            if let queryText = arguments["queryText"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !queryText.isEmpty
            {
                return queryText
            }
            if let hoursRaw = arguments["rangeHours"],
               let hours = Int(hoursRaw),
               hours > 0
            {
                let dayOffset = Int(arguments["dayOffset"] ?? "0") ?? 0
                let anchor = arguments["anchor"]?.lowercased() ?? "dayStart"

                if anchor == "now", dayOffset == 0, hours < 24 {
                    return "Show my reminders for the next \(hours) hours."
                }

                if hours == 24 {
                    switch dayOffset {
                    case 1:
                        return "What reminders do I have tomorrow?"
                    case -1:
                        return "What reminders did I have yesterday?"
                    case 0:
                        return "What reminders do I have today?"
                    default:
                        return "Show my reminders for day offset \(dayOffset)."
                    }
                }
                return "Show my reminders for the next \(hours) hours."
            }
            return "What reminders do I have today?"
        case "desktop.cleanup":
            return "Organize my desktop files safely."
        case "messages.send":
            if let recipient = arguments["recipient"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recipient.isEmpty
            {
                return "Send a message to \(recipient)."
            }
            return "Send a message."
        case "apple.script.run":
            return "Run an AppleScript automation."
        case "files.read":
            if let path = arguments["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty
            {
                return "Read file details for \(path)."
            }
            return "Read file details."
        case "files.move":
            let source = arguments["sourcePath"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let destination = arguments["destinationPath"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !source.isEmpty, !destination.isEmpty {
                return "Move \(source) to \(destination)."
            }
            return "Move a file."
        default:
            return "Run \(displayName)."
        }
    }

    private func computerActionAssistantText(result: ComputerActionExecutionResult) -> String {
        let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = result.detailsMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)

        if details.isEmpty {
            return summary
        }
        if summary.isEmpty {
            return details
        }
        if details.caseInsensitiveCompare(summary) == .orderedSame {
            return details
        }
        return "\(summary)\n\n\(details)"
    }

    private func persistComputerActionTranscriptTurn(
        threadID: UUID,
        projectID: UUID,
        timestamp: Date,
        userText: String,
        assistantText: String,
        actionCard: ActionCard
    ) async {
        guard let projectRepository else {
            return
        }

        do {
            guard let project = try await projectRepository.getProject(id: projectID) else {
                return
            }

            let summary = ArchivedTurnSummary(
                timestamp: timestamp,
                status: .completed,
                userText: userText,
                assistantText: assistantText,
                actions: [actionCard]
            )

            _ = try await TurnPersistenceWorker.shared.persistArchive(
                projectPath: project.path,
                threadID: threadID,
                summary: summary,
                turnStatus: .completed
            )

            _ = try await threadRepository?.touchThread(id: threadID)
            try await chatSearchRepository?.indexMessageExcerpt(
                threadID: threadID,
                projectID: projectID,
                text: userText
            )
            if !assistantText.isEmpty {
                try await chatSearchRepository?.indexMessageExcerpt(
                    threadID: threadID,
                    projectID: projectID,
                    text: assistantText
                )
            }
        } catch {
            appendLog(
                .warning,
                "Failed to persist computer action transcript turn: \(error.localizedDescription)"
            )
        }
    }

    private func requiresExplicitConfirmation(for provider: any ComputerActionProvider) -> Bool {
        provider.requiresConfirmation || provider.safetyLevel != .readOnly
    }

    private func ensureComputerActionPermission(
        actionID: String,
        projectID: UUID,
        displayName: String,
        safetyLevel: ComputerActionSafetyLevel
    ) async throws -> Bool {
        if safetyLevel == .readOnly {
            return true
        }

        if requiresPerRunComputerActionPermissionPrompt(actionID: actionID) {
            return promptForComputerActionPermission(
                displayName: displayName,
                safetyLevel: safetyLevel
            )
        }

        guard let permissionRepository = computerActionPermissionRepository else {
            return true
        }

        if let existing = try await permissionRepository.get(actionID: actionID, projectID: projectID) {
            return existing.decision == .granted
        }

        let granted = promptForComputerActionPermission(
            displayName: displayName,
            safetyLevel: safetyLevel
        )

        if shouldPersistComputerActionPermissionDecision(actionID: actionID) {
            _ = try await permissionRepository.set(
                actionID: actionID,
                projectID: projectID,
                decision: granted ? .granted : .denied,
                decidedAt: Date()
            )
        }
        return granted
    }

    func requiresPerRunComputerActionPermissionPrompt(actionID: String) -> Bool {
        actionID == "apple.script.run"
    }

    func shouldPersistComputerActionPermissionDecision(actionID: String) -> Bool {
        !requiresPerRunComputerActionPermissionPrompt(actionID: actionID)
    }

    private func promptForComputerActionPermission(
        displayName: String,
        safetyLevel: ComputerActionSafetyLevel
    ) -> Bool {
        if let computerActionPermissionPromptHandler {
            return computerActionPermissionPromptHandler(displayName, safetyLevel)
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow \(displayName)?"
        alert.informativeText = switch safetyLevel {
        case .readOnly:
            "This action reads local data and does not make changes."
        case .externallyVisible:
            "This action can send externally visible output (for example, Messages)."
        case .destructive:
            "This action can move or modify local files. A preview is required before execution."
        }
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func permissionRecoveryTargetForComputerAction(
        actionID: String,
        error: ComputerActionError,
        arguments: [String: String] = [:]
    ) -> PermissionRecoveryTarget? {
        guard case let .permissionDenied(message) = error else {
            return nil
        }

        let normalizedMessage = message.lowercased()
        switch actionID {
        case "messages.send":
            guard normalizedMessage.contains("automation")
                || normalizedMessage.contains("messages permissions")
                || normalizedMessage.contains("apple events")
            else {
                return nil
            }
            return .automation

        case "calendar.today", "calendar.create", "calendar.update", "calendar.delete":
            guard normalizedMessage.contains("calendar") else {
                return nil
            }
            return .calendars

        case "reminders.today":
            guard normalizedMessage.contains("reminder") else {
                return nil
            }
            return .reminders

        case "apple.script.run":
            guard isLikelySystemPermissionFailureMessage(normalizedMessage) else {
                return nil
            }

            if let hintedTarget = permissionRecoveryTarget(fromTargetHint: arguments["targetHint"]) {
                return hintedTarget
            }

            if normalizedMessage.contains("calendar") {
                return .calendars
            }
            if normalizedMessage.contains("reminder") {
                return .reminders
            }
            if normalizedMessage.contains("automation")
                || normalizedMessage.contains("apple event")
            {
                return .automation
            }
            return .genericAutomation

        default:
            return nil
        }
    }

    private func presentPermissionRecoveryNoticeIfNeeded(
        actionID: String,
        arguments: [String: String],
        error: Error,
        threadID: UUID?
    ) {
        guard let computerActionError = error as? ComputerActionError,
              let target = permissionRecoveryTargetForComputerAction(
                  actionID: actionID,
                  error: computerActionError,
                  arguments: arguments
              )
        else {
            return
        }

        permissionRecoveryNotice = PermissionRecoveryNotice(
            actionID: actionID,
            threadID: threadID,
            target: target,
            title: target.title,
            message: computerActionError.localizedDescription,
            remediationSteps: target.remediationSteps
        )
        syncApprovalPresentationState()
    }

    private func permissionRecoveryTarget(fromTargetHint hint: String?) -> PermissionRecoveryTarget? {
        guard let hint else {
            return nil
        }

        let normalized = hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        if normalized.contains("calendar") {
            return .calendars
        }
        if normalized.contains("reminder") {
            return .reminders
        }
        if normalized.contains("message")
            || normalized.contains("imessage")
            || normalized.contains("automation")
            || normalized.contains("appleevent")
            || normalized.contains("apple-event")
        {
            return .automation
        }

        if normalized.contains("script") || normalized.contains("generic") {
            return .genericAutomation
        }

        return nil
    }

    private func isLikelySystemPermissionFailureMessage(_ message: String) -> Bool {
        if message.contains("permission denied for"),
           !message.contains("system settings"),
           !message.contains("automation"),
           !message.contains("calendar"),
           !message.contains("reminder"),
           !message.contains("apple event")
        {
            return false
        }

        let indicators = [
            "automation",
            "calendar",
            "reminder",
            "apple event",
            "not authorized",
            "not permitted",
            "privacy",
            "enable",
            "access is denied",
            "-1743",
            "erraeeventnotpermitted",
        ]

        return indicators.contains(where: { message.contains($0) })
    }

    func dismissPermissionRecoveryNotice() {
        permissionRecoveryNotice = nil
        syncApprovalPresentationState()
    }

    func openPermissionRecoverySettingsFromNotice() {
        guard let notice = permissionRecoveryNotice else {
            return
        }
        openSystemSettings(for: notice.target)
    }

    func openPermissionRecoverySettings(for target: PermissionRecoveryTarget) {
        openSystemSettings(for: target)
    }

    private func openSystemSettings(for target: PermissionRecoveryTarget) {
        for candidate in target.deepLinkCandidates {
            guard let url = URL(string: candidate) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return
            }
        }

        let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        NSWorkspace.shared.open(fallback)
    }

    private func persistComputerActionRun(_ record: ComputerActionRunRecord) async throws {
        guard let computerActionRunRepository else {
            return
        }
        _ = try await computerActionRunRepository.upsert(record)
    }

    private func encodePreviewArtifact(_ artifact: ComputerActionPreviewArtifact) -> String? {
        guard let data = try? JSONEncoder().encode(artifact) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func encodeDictionary(_ dictionary: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(dictionary) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func decodeDictionary(from text: String?) -> [String: String]? {
        guard let text,
              let data = text.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    var areNativeComputerActionsEnabled: Bool {
        codexConfigDocument
            .value(at: [.key("features"), .key("native_computer_actions")])?
            .booleanValue ?? true
    }
}
