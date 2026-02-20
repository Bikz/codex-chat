import AppKit
import CodexChatCore
import CodexComputerActions
import CodexKit
import Foundation

extension AppModel {
    enum PermissionRecoveryTarget: Equatable {
        case automation
        case calendars

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
            }
        }

        var title: String {
            switch self {
            case .automation:
                "Automation permission needed"
            case .calendars:
                "Calendar permission needed"
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

        let preview = try await provider.preview(request: request)
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
            presentPermissionRecoveryPromptIfNeeded(actionID: provider.actionID, error: error)
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

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: previewState.threadID,
                    method: "computer_action/execute",
                    title: "\(provider.displayName) completed",
                    detail: result.detailsMarkdown
                )
            ),
            to: previewState.threadID
        )

        computerActionStatusMessage = result.summary
        pendingComputerActionPreview = nil
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

        _ = try await permissionRepository.set(
            actionID: actionID,
            projectID: projectID,
            decision: granted ? .granted : .denied,
            decidedAt: Date()
        )
        return granted
    }

    private func promptForComputerActionPermission(
        displayName: String,
        safetyLevel: ComputerActionSafetyLevel
    ) -> Bool {
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
        error: ComputerActionError
    ) -> PermissionRecoveryTarget? {
        guard case let .permissionDenied(message) = error else {
            return nil
        }

        let normalizedMessage = message.lowercased()
        switch actionID {
        case "messages.send":
            guard normalizedMessage.contains("automation")
                || normalizedMessage.contains("messages permissions")
            else {
                return nil
            }
            return .automation

        case "calendar.today":
            guard normalizedMessage.contains("calendar") else {
                return nil
            }
            return .calendars

        default:
            return nil
        }
    }

    private func presentPermissionRecoveryPromptIfNeeded(actionID: String, error: Error) {
        guard let computerActionError = error as? ComputerActionError,
              let target = permissionRecoveryTargetForComputerAction(
                  actionID: actionID,
                  error: computerActionError
              )
        else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = target.title
        alert.informativeText = "\(computerActionError.localizedDescription)\n\nOpen System Settings to grant access?"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not now")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings(for: target)
        }
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
