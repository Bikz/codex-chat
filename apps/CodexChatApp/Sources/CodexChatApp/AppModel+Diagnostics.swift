import AppKit
import Foundation

extension AppModel {
    struct AutomationTimelineEventRollup: Identifiable, Hashable, Sendable {
        let id: String
        let latestEvent: ExtensibilityDiagnosticEvent
        let earliestTimestamp: Date
        let occurrenceCount: Int

        var durationSeconds: TimeInterval {
            max(0, latestEvent.timestamp.timeIntervalSince(earliestTimestamp))
        }
    }

    private enum ExtensibilityRerunCommandClass: String, Sendable {
        case git
        case npxSkillsAdd
        case launchctl

        var label: String {
            switch self {
            case .git:
                "git"
            case .npxSkillsAdd:
                "npx skills add"
            case .launchctl:
                "launchctl"
            }
        }
    }

    private enum ExtensibilityRerunPolicyDecision: Sendable {
        case allow(ExtensibilityRerunCommandClass)
        case deny(String)
    }

    static func rollupAutomationTimelineEvents(
        _ events: [ExtensibilityDiagnosticEvent],
        collapseWindowSeconds: TimeInterval = 180
    ) -> [AutomationTimelineEventRollup] {
        guard !events.isEmpty else { return [] }

        var rollups: [AutomationTimelineEventRollup] = []
        rollups.reserveCapacity(events.count)

        for event in events {
            let eventFingerprint = automationTimelineFingerprint(for: event)
            if let lastIndex = rollups.indices.last {
                let lastRollup = rollups[lastIndex]
                let lastFingerprint = automationTimelineFingerprint(for: lastRollup.latestEvent)
                let isWithinCollapseWindow = lastRollup.latestEvent.timestamp.timeIntervalSince(event.timestamp) <= collapseWindowSeconds
                if eventFingerprint == lastFingerprint, isWithinCollapseWindow {
                    rollups[lastIndex] = AutomationTimelineEventRollup(
                        id: lastRollup.id,
                        latestEvent: lastRollup.latestEvent,
                        earliestTimestamp: min(lastRollup.earliestTimestamp, event.timestamp),
                        occurrenceCount: lastRollup.occurrenceCount + 1
                    )
                    continue
                }
            }

            rollups.append(
                AutomationTimelineEventRollup(
                    id: event.id.uuidString,
                    latestEvent: event,
                    earliestTimestamp: event.timestamp,
                    occurrenceCount: 1
                )
            )
        }

        return rollups
    }

    func toggleDiagnostics() {
        isDiagnosticsVisible.toggle()
        appendLog(.debug, "Diagnostics toggled: \(isDiagnosticsVisible)")
    }

    func closeDiagnostics() {
        isDiagnosticsVisible = false
    }

    func setAutomationTimelineFocusFilter(_ filter: AutomationTimelineFocusFilter) {
        guard automationTimelineFocusFilter != filter else { return }
        automationTimelineFocusFilter = filter
        persistAutomationTimelineFocusFilterIfNeeded()
    }

    func copyDiagnosticsBundle() {
        do {
            let snapshot = DiagnosticsBundleSnapshot(
                generatedAt: Date(),
                runtimeStatus: runtimeStatus,
                runtimeIssue: runtimeIssue?.message,
                accountSummary: accountSummaryText,
                logs: logs
            )
            let bundleURL = try DiagnosticsBundleExporter.export(snapshot: snapshot)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bundleURL.path, forType: .string)
            accountStatusMessage = "Diagnostics bundle created and copied: \(bundleURL.lastPathComponent)"
            appendLog(.info, "Diagnostics bundle exported")
        } catch DiagnosticsBundleExporterError.cancelled {
            appendLog(.debug, "Diagnostics export cancelled")
        } catch {
            accountStatusMessage = "Failed to export diagnostics: \(error.localizedDescription)"
            appendLog(.error, "Diagnostics export failed: \(error.localizedDescription)")
        }
    }

    func copyExtensibilityDiagnostics() {
        do {
            let snapshot = ExtensibilityDiagnosticsSnapshot(
                generatedAt: Date(),
                retentionLimit: extensibilityDiagnosticsRetentionLimit,
                events: extensibilityDiagnostics
            )
            let destinationURL = try ExtensibilityDiagnosticsExporter.export(snapshot: snapshot)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(destinationURL.path, forType: .string)
            accountStatusMessage = "Extensibility diagnostics exported and copied: \(destinationURL.lastPathComponent)"
            appendLog(.info, "Extensibility diagnostics exported")
        } catch ExtensibilityDiagnosticsExporterError.cancelled {
            appendLog(.debug, "Extensibility diagnostics export cancelled")
        } catch {
            accountStatusMessage = "Failed to export extensibility diagnostics: \(error.localizedDescription)"
            appendLog(.error, "Extensibility diagnostics export failed: \(error.localizedDescription)")
        }
    }

    func prepareExtensibilityRerunCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            followUpStatusMessage = "No rerun command is available for this diagnostics entry."
            return
        }

        composerText = """
        Troubleshoot and safely rerun this command in the current project:
        ```
        \(trimmed)
        ```
        """
        followUpStatusMessage = "Prepared a safe rerun prompt in the composer. Review and send when ready."
        appendLog(.info, "Prepared extensibility rerun prompt in composer")
    }

    func isExtensibilityRerunCommandAllowlisted(_ command: String) -> Bool {
        if case .allow = extensibilityRerunPolicy(for: command) {
            return true
        }
        return false
    }

    func extensibilityRerunCommandPolicyMessage(_ command: String) -> String {
        switch extensibilityRerunPolicy(for: command) {
        case let .allow(commandClass):
            "Allowlisted direct rerun class: \(commandClass.label)."
        case let .deny(reason):
            "Direct rerun blocked: \(reason)"
        }
    }

    func executeAllowlistedExtensibilityRerunCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        switch extensibilityRerunPolicy(for: trimmed) {
        case let .allow(commandClass):
            guard canSubmitComposer else {
                prepareExtensibilityRerunCommand(trimmed)
                followUpStatusMessage = "Command is allowlisted, but chat is not ready. Review the prepared rerun prompt and send when ready."
                appendLog(.warning, "Allowlisted rerun command prepared but dispatch prerequisites were not met")
                return
            }

            composerText = """
            Run this allowlisted extensibility recovery command exactly once in the current project:
            ```bash
            \(trimmed)
            ```
            Before running, restate the command and confirm no extra chained commands will be used. After running, summarize stdout/stderr and final status.
            """
            submitComposerWithQueuePolicy()
            followUpStatusMessage = "Queued allowlisted rerun command (\(commandClass.label))."
            appendLog(.info, "Queued allowlisted extensibility rerun command: \(trimmed)")

        case let .deny(reason):
            followUpStatusMessage = "Direct rerun blocked: \(reason)"
            appendLog(.warning, "Blocked non-allowlisted rerun command: \(trimmed)")
        }
    }

    func restoreAutomationTimelineFocusFilterIfNeeded() async {
        guard let preferenceRepository else {
            automationTimelineFocusFilter = .all
            return
        }
        do {
            guard let raw = try await preferenceRepository.getPreference(key: .extensibilityAutomationTimelineFocusFilterV1),
                  let restored = AutomationTimelineFocusFilter(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                automationTimelineFocusFilter = .all
                return
            }
            automationTimelineFocusFilter = restored
        } catch {
            appendLog(.warning, "Failed to restore automation timeline focus filter: \(error.localizedDescription)")
            automationTimelineFocusFilter = .all
        }
    }

    private func persistAutomationTimelineFocusFilterIfNeeded() {
        guard let preferenceRepository else { return }
        let snapshot = automationTimelineFocusFilter.rawValue
        automationTimelineFocusFilterPersistenceTask?.cancel()
        automationTimelineFocusFilterPersistenceTask = Task { [weak self] in
            do {
                try await preferenceRepository.setPreference(
                    key: .extensibilityAutomationTimelineFocusFilterV1,
                    value: snapshot
                )
            } catch {
                self?.appendLog(.warning, "Failed to persist automation timeline focus filter: \(error.localizedDescription)")
            }
        }
    }

    private static func automationTimelineFingerprint(for event: ExtensibilityDiagnosticEvent) -> String {
        [
            event.surface,
            event.operation,
            event.kind,
            event.modID ?? "",
            event.projectID?.uuidString ?? "",
            event.threadID?.uuidString ?? "",
            event.command,
            event.summary,
        ].joined(separator: "|")
    }

    private func extensibilityRerunPolicy(for command: String) -> ExtensibilityRerunPolicyDecision {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .deny("No command was provided.")
        }

        if trimmed.count > 500 {
            return .deny("Command exceeds the allowlisted length limit.")
        }

        let forbiddenFragments = ["\n", "\r", "&&", "||", ";", "|", ">", "<", "`", "$("]
        if forbiddenFragments.contains(where: trimmed.contains) {
            return .deny("Shell chaining or redirection operators are not allowed.")
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let head = tokens.first?.lowercased() else {
            return .deny("No command was provided.")
        }

        switch head {
        case "git":
            guard tokens.count >= 2 else {
                return .deny("Git subcommand is required.")
            }
            let allowedSubcommands: Set<String> = ["clone", "pull", "fetch", "submodule", "ls-remote"]
            let subcommand = tokens[1].lowercased()
            guard allowedSubcommands.contains(subcommand) else {
                return .deny("Only git clone/pull/fetch/submodule/ls-remote are allowlisted.")
            }
            return .allow(.git)

        case "npx":
            let lowered = tokens.map { $0.lowercased() }
            guard lowered.count >= 3, lowered[1] == "skills", lowered[2] == "add" else {
                return .deny("Only `npx skills add` is allowlisted for direct reruns.")
            }
            return .allow(.npxSkillsAdd)

        case "launchctl":
            guard tokens.count >= 2 else {
                return .deny("launchctl subcommand is required.")
            }
            let allowedSubcommands: Set<String> = ["bootstrap", "bootout", "kickstart", "print", "enable", "disable"]
            let subcommand = tokens[1].lowercased()
            guard allowedSubcommands.contains(subcommand) else {
                return .deny("Only bootstrap/bootout/kickstart/print/enable/disable are allowlisted.")
            }
            return .allow(.launchctl)

        default:
            return .deny("Command class is not allowlisted.")
        }
    }
}
