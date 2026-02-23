import AppKit
import CodexChatCore
import CodexExtensions
import CodexMods
import Darwin
import Foundation

extension AppModel {
    private struct PersistedModsBarUIState: Codable, Sendable {
        var isVisible: Bool
        var presentationMode: ModsBarPresentationMode
        var lastOpenPresentationMode: ModsBarPresentationMode?
    }

    private enum PersonalNotesModsBarConstants {
        static let canonicalModID = "codexchat.personal-notes"
        static let actionHookID = "notes-action"
        static let titleToken = "personal-notes"
        static let emptyStateMarkdown = "_Start typing to save project-specific notes. Notes autosave for this project._"
        static let legacyThreadEmptyStateMarkdown = "_Start typing to save thread-specific notes. Notes autosave for this chat._"
        static let legacyEmptyStateMarkdown = "_No notes yet. Use Add or Edit to save thread-specific notes._"
    }

    private enum PromptBookModsBarConstants {
        static let canonicalModID = "codexchat.prompt-book"
        static let actionHookID = "prompt-book-action"
        static let titleToken = "prompt-book"
        static let maxPrompts = 12
    }

    private enum ExtensionAutomationStatus {
        static let ok = "ok"
        static let failed = "failed"
        static let permissionDenied = "permission-denied"
        static let launchdScheduled = "launchd-scheduled"
        static let launchdFailed = "launchd-failed"
        static let launchdPermissionDenied = "launchd-permission-denied"

        static let failingStatuses: Set<String> = [
            failed,
            permissionDenied,
            launchdFailed,
            launchdPermissionDenied,
        ]

        static let launchdScheduledStatuses: Set<String> = [
            launchdScheduled,
            "scheduled", // Backward compatibility for pre-migration records.
        ]

        static let launchdFailingStatuses: Set<String> = [
            launchdFailed,
            launchdPermissionDenied,
        ]
    }

    private struct PromptBookStatePayload: Decodable {
        struct Prompt: Decodable {
            let id: String?
            let title: String?
            let text: String?
        }

        let prompts: [Prompt]
    }

    func toggleModsBar() {
        guard canToggleModsBarForSelectedThread else { return }
        let next = !extensionModsBarIsVisible
        extensionModsBarIsVisible = next
        if next {
            if extensionModsBarPresentationMode == .rail {
                extensionModsBarPresentationMode = restoredOpenPresentationMode()
            } else {
                rememberOpenPresentationMode(extensionModsBarPresentationMode)
            }
        }
        Task { try? await persistModsBarVisibilityPreference() }
    }

    func setModsBarPresentationMode(_ mode: ModsBarPresentationMode) {
        guard canToggleModsBarForSelectedThread else { return }
        extensionModsBarPresentationMode = mode
        rememberOpenPresentationMode(mode)
        if !extensionModsBarIsVisible {
            extensionModsBarIsVisible = true
        }
        Task { try? await persistModsBarVisibilityPreference() }
    }

    func cycleModsBarPresentationMode() {
        guard canToggleModsBarForSelectedThread else { return }
        guard isModsBarVisibleForSelectedThread else {
            setModsBarPresentationMode(.peek)
            return
        }

        let nextMode: ModsBarPresentationMode = switch selectedModsBarPresentationMode {
        case .rail:
            .peek
        case .peek:
            .expanded
        case .expanded:
            .rail
        }
        setModsBarPresentationMode(nextMode)
    }

    func restoreModsBarVisibility() async {
        guard let preferenceRepository else { return }
        do {
            let raw: String? = if let current = try await preferenceRepository.getPreference(
                key: .extensionsModsBarVisibilityByThread
            ) {
                current
            } else {
                try await preferenceRepository.getPreference(key: .extensionsLegacyModsBarVisibility)
            }
            guard let raw,
                  let data = raw.data(using: .utf8)
            else {
                extensionModsBarIsVisible = false
                extensionModsBarPresentationMode = .peek
                extensionModsBarLastOpenPresentationMode = .peek
                return
            }

            if let decoded = try? JSONDecoder().decode(PersistedModsBarUIState.self, from: data) {
                extensionModsBarIsVisible = decoded.isVisible
                extensionModsBarPresentationMode = decoded.presentationMode
                if let lastOpenPresentationMode = decoded.lastOpenPresentationMode {
                    rememberOpenPresentationMode(lastOpenPresentationMode)
                } else {
                    rememberOpenPresentationMode(decoded.presentationMode)
                }
                return
            }

            if let decodedLegacyMap = try? JSONDecoder().decode([String: Bool].self, from: data) {
                extensionModsBarIsVisible = decodedLegacyMap.values.contains(true)
                extensionModsBarPresentationMode = .peek
                extensionModsBarLastOpenPresentationMode = .peek
                return
            }

            if let decodedBool = try? JSONDecoder().decode(Bool.self, from: data) {
                extensionModsBarIsVisible = decodedBool
                extensionModsBarPresentationMode = .peek
                extensionModsBarLastOpenPresentationMode = .peek
                return
            }

            extensionModsBarIsVisible = false
            extensionModsBarPresentationMode = .peek
            extensionModsBarLastOpenPresentationMode = .peek
        } catch {
            appendLog(.warning, "Failed to restore modsBar visibility state: \(error.localizedDescription)")
        }
    }

    func persistModsBarVisibilityPreference() async throws {
        guard let preferenceRepository else { return }
        let state = PersistedModsBarUIState(
            isVisible: extensionModsBarIsVisible,
            presentationMode: extensionModsBarPresentationMode,
            lastOpenPresentationMode: extensionModsBarLastOpenPresentationMode
        )
        let data = try JSONEncoder().encode(state)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await preferenceRepository.setPreference(key: .extensionsModsBarVisibilityByThread, value: text)
    }

    func syncActiveExtensions(
        globalMods: [DiscoveredUIMod],
        projectMods: [DiscoveredUIMod],
        selectedGlobalPath: String?,
        selectedProjectPath: String?,
        installRecords: [ExtensionInstallRecord]
    ) {
        let selectedGlobalMod = globalMods.first(where: { $0.directoryPath == selectedGlobalPath })
        let selectedProjectMod = projectMods.first(where: { $0.directoryPath == selectedProjectPath })

        let activeGlobalMods = globalMods.filter { mod in
            isModRuntimeEnabled(
                mod,
                scope: .global,
                projectID: nil,
                selectedPath: selectedGlobalPath,
                installRecords: installRecords
            )
        }
        let activeProjectMods = projectMods.filter { mod in
            isModRuntimeEnabled(
                mod,
                scope: .project,
                projectID: selectedProjectID,
                selectedPath: selectedProjectPath,
                installRecords: installRecords
            )
        }

        var hooks: [ResolvedExtensionHook] = []
        var automations: [ResolvedExtensionAutomation] = []

        for globalMod in activeGlobalMods {
            hooks.append(contentsOf: globalMod.definition.hooks.map {
                ResolvedExtensionHook(modID: globalMod.definition.manifest.id, modDirectoryPath: globalMod.directoryPath, definition: $0)
            })
            automations.append(contentsOf: globalMod.definition.automations.map {
                ResolvedExtensionAutomation(modID: globalMod.definition.manifest.id, modDirectoryPath: globalMod.directoryPath, definition: $0)
            })
        }

        for projectMod in activeProjectMods {
            hooks.append(contentsOf: projectMod.definition.hooks.map {
                ResolvedExtensionHook(modID: projectMod.definition.manifest.id, modDirectoryPath: projectMod.directoryPath, definition: $0)
            })
            automations.append(contentsOf: projectMod.definition.automations.map {
                ResolvedExtensionAutomation(modID: projectMod.definition.manifest.id, modDirectoryPath: projectMod.directoryPath, definition: $0)
            })
        }

        activeExtensionHooks = hooks
        activeExtensionAutomations = automations

        let resolvedProjectModsBarMod = (
            selectedProjectMod.flatMap { mod in activeProjectMods.contains(mod) ? mod : nil }
        ) ?? activeProjectMods.first(where: { $0.definition.uiSlots?.modsBar?.enabled == true })
        let resolvedGlobalModsBarMod = (
            selectedGlobalMod.flatMap { mod in activeGlobalMods.contains(mod) ? mod : nil }
        ) ?? activeGlobalMods.first(where: { $0.definition.uiSlots?.modsBar?.enabled == true })

        if let projectModsBar = resolvedProjectModsBarMod?.definition.uiSlots?.modsBar {
            activeModsBarSlot = projectModsBar
            activeModsBarModID = resolvedProjectModsBarMod?.definition.manifest.id
            activeModsBarModDirectoryPath = resolvedProjectModsBarMod?.directoryPath
        } else if let globalModsBar = resolvedGlobalModsBarMod?.definition.uiSlots?.modsBar {
            activeModsBarSlot = globalModsBar
            activeModsBarModID = resolvedGlobalModsBarMod?.definition.manifest.id
            activeModsBarModDirectoryPath = resolvedGlobalModsBarMod?.directoryPath
        } else {
            activeModsBarSlot = nil
            activeModsBarModID = nil
            activeModsBarModDirectoryPath = nil
            extensionModsBarByProjectID = [:]
            extensionGlobalModsBarState = nil
        }

        Task {
            await refreshAutomationScheduler()
            await loadModsBarCacheForSelectedThread()
        }
    }

    private func isModRuntimeEnabled(
        _ mod: DiscoveredUIMod,
        scope: ModScope,
        projectID: UUID?,
        selectedPath: String?,
        installRecords: [ExtensionInstallRecord]
    ) -> Bool {
        let installScope: ExtensionInstallScope = switch scope {
        case .global:
            .global
        case .project:
            .project
        }

        let matchingRecord = installRecords.first(where: { record in
            guard record.scope == installScope,
                  record.modID == mod.definition.manifest.id
            else {
                return false
            }
            if installScope == .project {
                return record.projectID == projectID
            }
            return true
        })

        if let matchingRecord {
            return matchingRecord.enabled
        }

        if selectedPath == mod.directoryPath {
            return true
        }

        let normalizedPath = NSString(string: mod.directoryPath).standardizingPath
        if normalizedPath.contains("/mods/first-party/") {
            return true
        }
        return mod.definition.manifest.id.lowercased().hasPrefix("codexchat.")
    }

    func refreshAutomationScheduler() async {
        let automations = activeExtensionAutomations.map { resolved in
            ExtensionAutomationDefinition(
                id: resolved.definition.id,
                schedule: resolved.definition.schedule,
                handler: ExtensionHandlerDefinition(
                    command: resolved.definition.handler.command,
                    cwd: resolved.definition.handler.cwd
                ),
                permissions: mapPermissions(resolved.definition.permissions),
                timeoutMs: resolved.definition.timeoutMs
            )
        }

        await extensionAutomationScheduler.replaceAutomations(automations) { [weak self] automation in
            guard let self else { return false }
            return await executeAutomation(automationID: automation.id)
        }

        await configureBackgroundAutomationIfNeeded()
    }

    func stopExtensionAutomations() async {
        await extensionAutomationScheduler.stopAll()
    }

    func refreshModsBarForSelectedThread() async {
        await loadModsBarCacheForSelectedThread()
    }

    var isPersonalNotesModsBarActiveForSelectedThread: Bool {
        (
            isLikelyPersonalNotesModID(activeModsBarModID)
                || activeModsBarTitleContains(PersonalNotesModsBarConstants.titleToken)
        )
            && (!isActiveModsBarThreadRequired || selectedThreadID != nil)
            && (activeModsBarSlot?.enabled ?? false)
    }

    var isPromptBookModsBarActiveForSelectedThread: Bool {
        (
            isLikelyPromptBookModID(activeModsBarModID)
                || activeModsBarTitleContains(PromptBookModsBarConstants.titleToken)
        )
            && (!isActiveModsBarThreadRequired || selectedThreadID != nil)
            && (activeModsBarSlot?.enabled ?? false)
    }

    func personalNotesEditorText(from markdown: String?) -> String {
        guard let markdown else { return "" }
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == PersonalNotesModsBarConstants.emptyStateMarkdown
            || trimmed == PersonalNotesModsBarConstants.legacyThreadEmptyStateMarkdown
            || trimmed == PersonalNotesModsBarConstants.legacyEmptyStateMarkdown
        {
            return ""
        }
        return markdown
    }

    func upsertPersonalNotesInline(_ text: String) {
        guard isPersonalNotesModsBarActiveForSelectedThread,
              let context = activeModsBarActionContext(requireThread: isActiveModsBarThreadRequired)
        else {
            return
        }

        guard let targetHookID = resolvedActiveModsBarActionHookID(
            preferredHookID: PersonalNotesModsBarConstants.actionHookID
        ) else {
            extensionStatusMessage = "Personal Notes mod is missing a modsBar.action hook."
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: String] = [
            "targetHookID": targetHookID,
            "targetModID": resolvedActiveModsBarTargetModID(
                fallbackModID: PersonalNotesModsBarConstants.canonicalModID
            ),
        ]
        if trimmed.isEmpty {
            payload["operation"] = "clear"
        } else {
            payload["operation"] = "upsert"
            payload["input"] = text
        }

        emitExtensionEvent(
            .modsBarAction,
            projectID: context.projectID,
            projectPath: context.projectPath,
            threadID: context.threadID,
            payload: payload
        )
    }

    func promptBookEntriesFromState() -> [PromptBookEntry] {
        guard isPromptBookModsBarActiveForSelectedThread,
              let stateURL = promptBookStateFileURL()
        else {
            return []
        }

        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return promptBookDefaultEntries()
        }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoded = try JSONDecoder().decode(PromptBookStatePayload.self, from: data)
            let normalized = normalizedPromptBookEntries(decoded.prompts.map { prompt in
                PromptBookEntry(
                    id: prompt.id ?? UUID().uuidString.lowercased(),
                    title: prompt.title ?? "",
                    text: prompt.text ?? ""
                )
            })
            return normalized.isEmpty ? promptBookDefaultEntries() : normalized
        } catch {
            appendLog(.warning, "Failed reading Prompt Book state: \(error.localizedDescription)")
            return promptBookDefaultEntries()
        }
    }

    func upsertPromptBookEntryInline(index: Int?, title: String, text: String) {
        guard isPromptBookModsBarActiveForSelectedThread,
              let context = activeModsBarActionContext(requireThread: false)
        else {
            return
        }

        guard let targetHookID = resolvedActiveModsBarActionHookID(
            preferredHookID: PromptBookModsBarConstants.actionHookID
        ) else {
            extensionStatusMessage = "Prompt Book mod is missing a modsBar.action hook."
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            extensionStatusMessage = "Prompt text cannot be empty."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedInput = trimmedTitle.isEmpty ? trimmedText : "\(trimmedTitle) :: \(trimmedText)"
        var payload: [String: String] = [
            "targetHookID": targetHookID,
            "targetModID": resolvedActiveModsBarTargetModID(
                fallbackModID: PromptBookModsBarConstants.canonicalModID
            ),
            "operation": index == nil ? "add" : "edit",
            "input": encodedInput,
        ]
        if let index {
            payload["index"] = String(index)
        }

        emitExtensionEvent(
            .modsBarAction,
            projectID: context.projectID,
            projectPath: context.projectPath,
            threadID: context.threadID,
            payload: payload
        )
    }

    func deletePromptBookEntryInline(index: Int) {
        guard isPromptBookModsBarActiveForSelectedThread,
              let context = activeModsBarActionContext(requireThread: false)
        else {
            return
        }

        guard let targetHookID = resolvedActiveModsBarActionHookID(
            preferredHookID: PromptBookModsBarConstants.actionHookID
        ) else {
            extensionStatusMessage = "Prompt Book mod is missing a modsBar.action hook."
            return
        }

        let payload: [String: String] = [
            "targetHookID": targetHookID,
            "targetModID": resolvedActiveModsBarTargetModID(
                fallbackModID: PromptBookModsBarConstants.canonicalModID
            ),
            "operation": "delete",
            "index": String(index),
        ]

        emitExtensionEvent(
            .modsBarAction,
            projectID: context.projectID,
            projectPath: context.projectPath,
            threadID: context.threadID,
            payload: payload
        )
    }

    func performModsBarAction(_ action: ExtensionModsBarOutput.Action) {
        switch action.kind {
        case .composerInsert:
            guard let text = action.payload["text"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                extensionStatusMessage = "Mods bar action is missing composer text."
                return
            }
            let existing = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
            composerText = existing.isEmpty ? text : "\(existing)\n\n\(text)"

        case .composerInsertAndSend:
            guard let text = action.payload["text"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                extensionStatusMessage = "Mods bar action is missing composer text."
                return
            }
            composerText = text
            sendMessage()

        case .emitEvent:
            emitModsBarActionEvent(action, input: nil)

        case .promptThenEmitEvent:
            guard let input = promptForModsBarActionInput(action) else { return }
            emitModsBarActionEvent(action, input: input)

        case .nativeAction:
            guard let selectedThreadID,
                  let context = extensionProjectContext(forThreadID: selectedThreadID)
            else {
                extensionStatusMessage = "Select a thread before running native actions."
                return
            }

            let nativeActionID = action.nativeActionID
                ?? action.payload["nativeActionID"]
                ?? action.payload["actionID"]

            guard let nativeActionID,
                  !nativeActionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                extensionStatusMessage = "Native action is missing an action ID."
                return
            }

            Task {
                do {
                    try await runNativeComputerAction(
                        actionID: nativeActionID,
                        arguments: action.payload,
                        threadID: selectedThreadID,
                        projectID: context.projectID
                    )
                    extensionStatusMessage = "Ran native action: \(nativeActionID)."
                } catch {
                    extensionStatusMessage = "Native action failed: \(error.localizedDescription)"
                    appendLog(.error, "Native action failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func emitExtensionEvent(
        _ event: ExtensionEventName,
        projectID: UUID,
        projectPath: String,
        threadID: UUID,
        turnID: String? = nil,
        turnStatus: String? = nil,
        payload: [String: String] = [:]
    ) {
        let envelope = ExtensionEventEnvelope(
            event: event,
            timestamp: Date(),
            project: ExtensionProjectContext(id: projectID.uuidString, path: projectPath),
            thread: ExtensionThreadContext(id: threadID.uuidString),
            turn: turnID.map { ExtensionTurnContext(id: $0, status: turnStatus) },
            payload: payload
        )

        Task {
            await extensionEventBus.publish(envelope)
            await runHooks(for: envelope)
        }
    }

    private func emitModsBarActionEvent(_ action: ExtensionModsBarOutput.Action, input: String?) {
        guard let context = activeModsBarActionContext(requireThread: false)
        else {
            extensionStatusMessage = "Select a project before using Mods bar actions."
            return
        }

        var payload = action.payload
        payload["actionId"] = action.id
        payload["actionKind"] = action.kind.rawValue
        if payload["targetModID"] == nil,
           let activeModsBarModID
        {
            payload["targetModID"] = activeModsBarModID
        }
        if let input {
            payload["input"] = input
        }

        emitExtensionEvent(
            .modsBarAction,
            projectID: context.projectID,
            projectPath: context.projectPath,
            threadID: context.threadID,
            payload: payload
        )
    }

    private func promptForModsBarActionInput(_ action: ExtensionModsBarOutput.Action) -> String? {
        let prompt = action.prompt
        let alert = NSAlert()
        alert.messageText = prompt?.title ?? action.label
        alert.informativeText = prompt?.message ?? "Enter a value."

        let field = NSTextField(string: prompt?.initialValue ?? "")
        field.placeholderString = prompt?.placeholder
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field

        alert.addButton(withTitle: prompt?.submitLabel ?? "Submit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    func extensionProjectContext(forThreadID threadID: UUID) -> (projectID: UUID, projectPath: String)? {
        if let activeTurnContext = activeTurnContext(for: threadID) {
            return (projectID: activeTurnContext.projectID, projectPath: activeTurnContext.projectPath)
        }

        if let selectedProject,
           selectedThreadID == threadID
        {
            return (projectID: selectedProject.id, projectPath: selectedProject.path)
        }

        let threadRecord = (threads + generalThreads + archivedThreads).first(where: { $0.id == threadID })
        guard let threadRecord,
              let project = projects.first(where: { $0.id == threadRecord.projectId })
        else {
            return nil
        }

        return (projectID: project.id, projectPath: project.path)
    }

    private func activeModsBarActionContext(requireThread: Bool) -> (projectID: UUID, projectPath: String, threadID: UUID)? {
        if let selectedThreadID,
           let context = extensionProjectContext(forThreadID: selectedThreadID)
        {
            return (context.projectID, context.projectPath, selectedThreadID)
        }

        guard !requireThread,
              let selectedProject
        else {
            return nil
        }

        // Synthetic thread context for draft mode events when no thread is selected.
        return (selectedProject.id, selectedProject.path, selectedProject.id)
    }

    func runHooks(for envelope: ExtensionEventEnvelope) async {
        guard !activeExtensionHooks.isEmpty else { return }

        let hooks = activeExtensionHooks.filter { $0.definition.event.rawValue == envelope.event.rawValue }
        guard !hooks.isEmpty else { return }

        for resolved in hooks {
            if envelope.event == .modsBarAction {
                if let targetModID = envelope.payload["targetModID"],
                   resolved.modID != targetModID
                {
                    continue
                }
                if let targetHookID = envelope.payload["targetHookID"],
                   resolved.definition.id != targetHookID
                {
                    continue
                }
            }

            let debounceMs = max(0, resolved.definition.debounceMs)
            if debounceMs > 0 {
                let key = "\(resolved.modID):\(resolved.definition.id)"
                if let last = extensionHookDebounceTimestamps[key], Date().timeIntervalSince(last) * 1000 < Double(debounceMs) {
                    continue
                }
                extensionHookDebounceTimestamps[key] = Date()
            }

            let permitted = await ensurePermissions(
                modID: resolved.modID,
                permissions: resolved.definition.permissions,
                projectID: UUID(uuidString: envelope.project.id),
                contextHint: "Hook \(resolved.definition.id)"
            )
            guard permitted else {
                await markHookState(resolved: resolved, status: "permission-denied", error: "Permissions not granted")
                continue
            }

            do {
                let runResult = try await extensionWorkerRunner.run(
                    handler: ExtensionHandlerDefinition(
                        command: resolved.definition.handler.command,
                        cwd: resolved.definition.handler.cwd
                    ),
                    input: ExtensionWorkerInput(envelope: envelope),
                    workingDirectory: URL(fileURLWithPath: resolved.modDirectoryPath, isDirectory: true),
                    timeoutMs: resolved.definition.timeoutMs
                )

                await applyWorkerOutput(
                    runResult.output,
                    envelope: envelope,
                    modDirectoryPath: resolved.modDirectoryPath,
                    sourceHookID: resolved.definition.id
                )
                await markHookState(resolved: resolved, status: "ok", error: nil)
            } catch {
                let details = Self.extensibilityProcessFailureDetails(from: error)
                let errorMessage = details?.summary ?? sanitizeExtensionLog(error.localizedDescription)
                if let details {
                    recordExtensibilityDiagnostic(surface: "extensions", operation: "hook", details: details)
                    appendLog(
                        .warning,
                        "Extension hook \(resolved.definition.id) failed [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                    )
                } else {
                    appendLog(.warning, "Extension hook \(resolved.definition.id) failed: \(errorMessage)")
                }
                await markHookState(resolved: resolved, status: "failed", error: errorMessage)
            }
        }
    }

    func executeAutomation(automationID: String) async -> Bool {
        guard let resolved = activeExtensionAutomations.first(where: { $0.definition.id == automationID }),
              let project = selectedProject,
              let threadID = selectedThreadID
        else {
            return false
        }

        let permissionOK = await ensurePermissions(
            modID: resolved.modID,
            permissions: resolved.definition.permissions,
            projectID: project.id,
            contextHint: "Automation \(resolved.definition.id)"
        )
        guard permissionOK else {
            await markAutomationState(
                resolved: resolved,
                status: ExtensionAutomationStatus.permissionDenied,
                error: "Permissions not granted",
                nextRunAt: nil
            )
            return false
        }

        var input = ExtensionWorkerInput(
            envelope: ExtensionEventEnvelope(
                event: .transcriptPersisted,
                timestamp: Date(),
                project: .init(id: project.id.uuidString, path: project.path),
                thread: .init(id: threadID.uuidString),
                turn: nil,
                payload: ["automationId": resolved.definition.id]
            )
        )
        input.event = "automation.scheduled"

        do {
            let runResult = try await extensionWorkerRunner.run(
                handler: ExtensionHandlerDefinition(
                    command: resolved.definition.handler.command,
                    cwd: resolved.definition.handler.cwd
                ),
                input: input,
                workingDirectory: URL(fileURLWithPath: resolved.modDirectoryPath, isDirectory: true),
                timeoutMs: resolved.definition.timeoutMs
            )

            await applyWorkerOutput(
                runResult.output,
                envelope: ExtensionEventEnvelope(
                    event: .transcriptPersisted,
                    timestamp: Date(),
                    project: .init(id: project.id.uuidString, path: project.path),
                    thread: .init(id: threadID.uuidString),
                    payload: ["automationId": resolved.definition.id]
                ),
                modDirectoryPath: resolved.modDirectoryPath,
                sourceHookID: nil
            )

            let nextRun = try? CronSchedule(expression: resolved.definition.schedule).nextRun(after: Date())
            await markAutomationState(
                resolved: resolved,
                status: ExtensionAutomationStatus.ok,
                error: nil,
                nextRunAt: nextRun
            )
            return true
        } catch {
            let details = Self.extensibilityProcessFailureDetails(from: error)
            let errorMessage = details?.summary ?? sanitizeExtensionLog(error.localizedDescription)
            await markAutomationState(
                resolved: resolved,
                status: ExtensionAutomationStatus.failed,
                error: errorMessage,
                nextRunAt: nil
            )
            if let details {
                recordExtensibilityDiagnostic(surface: "extensions", operation: "automation", details: details)
                appendLog(
                    .warning,
                    "Extension automation \(resolved.definition.id) failed [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                )
            } else {
                appendLog(.warning, "Extension automation \(resolved.definition.id) failed: \(errorMessage)")
            }
            return false
        }
    }

    private func mapPermissions(_ permissions: ModExtensionPermissions) -> ExtensionPermissionSet {
        ExtensionPermissionSet(
            projectRead: permissions.projectRead,
            projectWrite: permissions.projectWrite,
            network: permissions.network,
            runtimeControl: permissions.runtimeControl,
            runWhenAppClosed: permissions.runWhenAppClosed
        )
    }

    private func requestedCorePermissions(_ permissions: ModExtensionPermissions) -> Set<CodexChatCore.ExtensionPermissionKey> {
        var requested = Set<CodexChatCore.ExtensionPermissionKey>()
        if permissions.projectRead { requested.insert(.projectRead) }
        if permissions.projectWrite { requested.insert(.projectWrite) }
        if permissions.network { requested.insert(.network) }
        if permissions.runtimeControl { requested.insert(.runtimeControl) }
        if permissions.runWhenAppClosed { requested.insert(.runWhenAppClosed) }
        return requested
    }

    private func requestedExtensibilityCapabilities(_ permissions: ModExtensionPermissions) -> Set<ExtensibilityCapability> {
        var required = Set<ExtensibilityCapability>()
        if permissions.projectRead { required.insert(.projectRead) }
        if permissions.projectWrite {
            required.insert(.projectWrite)
            required.insert(.filesystemWrite)
        }
        if permissions.network { required.insert(.network) }
        if permissions.runtimeControl { required.insert(.runtimeControl) }
        if permissions.runWhenAppClosed { required.insert(.runWhenAppClosed) }
        return required
    }

    private func ensurePermissions(
        modID: String,
        permissions: ModExtensionPermissions,
        projectID: UUID?,
        contextHint: String
    ) async -> Bool {
        guard let extensionPermissionRepository else {
            return false
        }

        let requested = requestedCorePermissions(permissions)
        guard !requested.isEmpty else {
            return true
        }

        let blockedCapabilities = blockedExtensibilityCapabilities(
            for: requestedExtensibilityCapabilities(permissions),
            projectID: projectID
        )
        if !blockedCapabilities.isEmpty {
            let blockedList = blockedCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
            appendLog(
                .warning,
                "Extension capabilities blocked in untrusted project for mod \(modID): \(blockedList)"
            )
            return false
        }

        do {
            let stored = try await extensionPermissionRepository.list(modID: modID)
            var granted = Set(stored.filter { $0.status == .granted }.map(\.permissionKey))
            let denied = Set(stored.filter { $0.status == .denied }.map(\.permissionKey))

            if !requested.isDisjoint(with: denied) {
                return false
            }

            let missing = requested.subtracting(granted)
            guard !missing.isEmpty else {
                return true
            }

            for key in missing {
                let status = promptForPermission(modID: modID, permission: key, contextHint: contextHint)
                try await extensionPermissionRepository.set(
                    modID: modID,
                    permissionKey: key,
                    status: status,
                    grantedAt: Date()
                )
                if status == .denied {
                    return false
                }
                granted.insert(key)
            }

            return requested.isSubset(of: granted)
        } catch {
            appendLog(.warning, "Extension permission check failed: \(error.localizedDescription)")
            return false
        }
    }

    private func promptForPermission(
        modID: String,
        permission: CodexChatCore.ExtensionPermissionKey,
        contextHint: String
    ) -> CodexChatCore.ExtensionPermissionStatus {
        let alert = NSAlert()
        alert.messageText = "Allow extension permission?"
        alert.informativeText = "\(contextHint) from mod `\(modID)` requests `\(permission.rawValue)` permission."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        return alert.runModal() == .alertFirstButtonReturn ? .granted : .denied
    }

    private func applyWorkerOutput(
        _ output: ExtensionWorkerOutput,
        envelope: ExtensionEventEnvelope,
        modDirectoryPath: String,
        sourceHookID: String?
    ) async {
        if let log = output.log, !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(.info, "[extension] \(sanitizeExtensionLog(log))")
        }

        if let modsBar = output.modsBar,
           shouldApplyModsBarOutput(sourceHookID: sourceHookID)
        {
            let threadID = UUID(uuidString: envelope.thread.id)
            let projectID = UUID(uuidString: envelope.project.id)
            let resolvedTitle = activeModsBarSlot?.title ?? modsBar.title
            let resolvedScope = modsBar.scope ?? .thread
            let resolvedActions = modsBar.actions ?? []
            let nextState = ExtensionModsBarState(
                title: resolvedTitle,
                markdown: modsBar.markdown,
                scope: resolvedScope,
                actions: resolvedActions,
                updatedAt: Date()
            )

            switch resolvedScope {
            case .thread:
                if let threadID {
                    extensionModsBarByThreadID[threadID] = nextState
                }
            case .project:
                if let projectID {
                    extensionModsBarByProjectID[projectID] = nextState
                }
            case .global:
                extensionGlobalModsBarState = nextState
            }

            do {
                _ = try await extensionStateStore.writeModsBarOutput(
                    output: ExtensionModsBarOutput(
                        title: resolvedTitle,
                        markdown: modsBar.markdown,
                        scope: resolvedScope,
                        actions: resolvedActions
                    ),
                    modDirectory: URL(fileURLWithPath: modDirectoryPath, isDirectory: true),
                    threadID: resolvedScope == .thread ? threadID : nil,
                    projectID: resolvedScope == .project ? projectID : nil
                )
            } catch {
                appendLog(.warning, "Failed to persist extension modsBar output: \(error.localizedDescription)")
            }

            if (resolvedScope != .thread || threadID != nil),
               !extensionModsBarIsVisible
            {
                extensionModsBarIsVisible = true
                extensionModsBarPresentationMode = restoredOpenPresentationMode()
                try? await persistModsBarVisibilityPreference()
            }
        }

        if let artifacts = output.artifacts {
            applyArtifacts(artifacts, projectPath: envelope.project.path)
        }
    }

    private func applyArtifacts(_ artifacts: [ExtensionArtifactInstruction], projectPath: String) {
        let fileManager = FileManager.default

        for artifact in artifacts {
            guard artifact.op == .upsert else { continue }
            let relative = artifact.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !relative.isEmpty else { continue }

            guard let destinationURL = ProjectPathSafety.destinationURL(
                for: relative,
                projectPath: projectPath
            ) else {
                appendLog(.warning, "Skipped extension artifact outside project root: \(relative)")
                continue
            }

            do {
                try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(artifact.content.utf8).write(to: destinationURL, options: [.atomic])
            } catch {
                appendLog(.warning, "Failed writing extension artifact \(relative): \(error.localizedDescription)")
            }
        }
    }

    private func markHookState(resolved: ResolvedExtensionHook, status: String, error: String?) async {
        guard let extensionHookStateRepository else { return }
        do {
            _ = try await extensionHookStateRepository.upsert(
                ExtensionHookStateRecord(
                    modID: resolved.modID,
                    hookID: resolved.definition.id,
                    lastRunAt: Date(),
                    lastStatus: status,
                    lastError: error
                )
            )
        } catch {
            appendLog(.warning, "Failed to persist extension hook state: \(error.localizedDescription)")
        }
    }

    private func markAutomationState(
        resolved: ResolvedExtensionAutomation,
        status: String,
        error: String?,
        nextRunAt: Date?
    ) async {
        guard let extensionAutomationStateRepository else { return }
        do {
            _ = try await extensionAutomationStateRepository.upsert(
                ExtensionAutomationStateRecord(
                    modID: resolved.modID,
                    automationID: resolved.definition.id,
                    nextRunAt: nextRunAt,
                    lastRunAt: Date(),
                    lastStatus: status,
                    lastError: error,
                    launchdLabel: launchdLabel(for: resolved)
                )
            )
            await refreshAutomationHealthSummary(for: resolved.modID)
        } catch {
            appendLog(.warning, "Failed to persist extension automation state: \(error.localizedDescription)")
        }
    }

    func refreshAutomationHealthSummaries(for modIDs: [String]) async {
        let uniqueModIDs = Array(Set(modIDs)).sorted()
        guard !uniqueModIDs.isEmpty else {
            extensionAutomationHealthByModID = [:]
            return
        }

        guard let extensionAutomationStateRepository else {
            extensionAutomationHealthByModID = [:]
            return
        }

        let previousByModID = extensionAutomationHealthByModID
        var next: [String: ExtensionAutomationHealthSummary] = [:]
        for modID in uniqueModIDs {
            do {
                let records = try await extensionAutomationStateRepository.list(modID: modID)
                let summary = Self.summarizeAutomationHealth(modID: modID, records: records)
                if let summary {
                    next[modID] = summary
                }
                emitAutomationHealthDiagnosticIfNeeded(
                    modID: modID,
                    previous: previousByModID[modID],
                    current: summary
                )
            } catch {
                appendLog(.warning, "Failed loading automation health for mod \(modID): \(error.localizedDescription)")
            }
        }

        extensionAutomationHealthByModID = next
    }

    func refreshAutomationHealthSummary(for modID: String) async {
        guard let extensionAutomationStateRepository else {
            extensionAutomationHealthByModID.removeValue(forKey: modID)
            return
        }

        let previous = extensionAutomationHealthByModID[modID]
        do {
            let records = try await extensionAutomationStateRepository.list(modID: modID)
            let summary = Self.summarizeAutomationHealth(modID: modID, records: records)
            if let summary {
                extensionAutomationHealthByModID[modID] = summary
            } else {
                extensionAutomationHealthByModID.removeValue(forKey: modID)
            }
            emitAutomationHealthDiagnosticIfNeeded(
                modID: modID,
                previous: previous,
                current: summary
            )
        } catch {
            appendLog(.warning, "Failed refreshing automation health for mod \(modID): \(error.localizedDescription)")
        }
    }

    static func summarizeAutomationHealth(
        modID: String,
        records: [ExtensionAutomationStateRecord]
    ) -> ExtensionAutomationHealthSummary? {
        guard !records.isEmpty else { return nil }

        let failingCount = records.count(where: { ExtensionAutomationStatus.failingStatuses.contains($0.lastStatus) })
        let launchdScheduledCount = records.count(where: {
            ExtensionAutomationStatus.launchdScheduledStatuses.contains($0.lastStatus)
        })
        let launchdFailingCount = records.count(where: {
            ExtensionAutomationStatus.launchdFailingStatuses.contains($0.lastStatus)
        })
        let nextRunAt = records.compactMap(\.nextRunAt).min()
        let latestRecord = records.max { lhs, rhs in
            let lhsDate = lhs.lastRunAt ?? .distantPast
            let rhsDate = rhs.lastRunAt ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.automationID < rhs.automationID
            }
            return lhsDate < rhsDate
        } ?? records[0]

        return ExtensionAutomationHealthSummary(
            modID: modID,
            automationCount: records.count,
            failingAutomationCount: failingCount,
            launchdScheduledAutomationCount: launchdScheduledCount,
            launchdFailingAutomationCount: launchdFailingCount,
            nextRunAt: nextRunAt,
            lastRunAt: latestRecord.lastRunAt,
            lastStatus: latestRecord.lastStatus,
            lastError: latestRecord.lastError
        )
    }

    private func launchdLabel(for resolved: ResolvedExtensionAutomation) -> String {
        let safeMod = resolved.modID.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
        let safeAutomation = resolved.definition.id.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
        return "app.codexchat.\(safeMod).\(safeAutomation)"
    }

    private func emitAutomationHealthDiagnosticIfNeeded(
        modID: String,
        previous: ExtensionAutomationHealthSummary?,
        current: ExtensionAutomationHealthSummary?
    ) {
        guard let current else { return }

        let wasFailing = (previous?.hasFailures ?? false) || (previous?.hasLaunchdFailures ?? false)
        let isFailing = current.hasFailures || current.hasLaunchdFailures
        guard isFailing else { return }

        let changedStatus = previous?.lastStatus != current.lastStatus
        let changedError = previous?.lastError != current.lastError
        guard !wasFailing || changedStatus || changedError else { return }

        var summary = "Mod \(modID) automation health reported \(current.lastStatus)."
        if let lastError = current.lastError, !lastError.isEmpty {
            summary += " \(lastError)"
        }

        let kind: ExtensibilityProcessFailureDetails.Kind = current.hasLaunchdFailures ? .launch : .command
        let details = ExtensibilityProcessFailureDetails(
            kind: kind,
            command: "automation-health",
            summary: summary
        )
        recordExtensibilityDiagnostic(
            surface: "automations",
            operation: "health",
            details: details
        )
    }

    private func shouldApplyModsBarOutput(sourceHookID: String?) -> Bool {
        guard let slot = activeModsBarSlot,
              slot.enabled
        else {
            return false
        }

        guard let source = slot.source else {
            return true
        }

        if source.type != "handlerOutput" {
            return false
        }

        guard let requiredHookID = source.hookID else {
            return true
        }
        return requiredHookID == sourceHookID
    }

    private func loadModsBarCacheForSelectedThread() async {
        guard let activeModsBarSlot,
              activeModsBarSlot.enabled
        else {
            return
        }

        let hookID = activeModsBarSlot.source?.hookID
        let modDirectoryPath: String? = activeModsBarModDirectoryPath ?? {
            if let hookID {
                return activeExtensionHooks.first(where: { $0.definition.id == hookID })?.modDirectoryPath
            }
            return activeExtensionHooks.first?.modDirectoryPath
        }()

        guard let modDirectoryPath else { return }

        do {
            if let selectedThreadID {
                let cachedThreadOutput = try await extensionStateStore.readModsBarOutput(
                    modDirectory: URL(fileURLWithPath: modDirectoryPath, isDirectory: true),
                    scope: .thread,
                    threadID: selectedThreadID,
                    projectID: nil
                )
                if let cachedThreadOutput,
                   !cachedThreadOutput.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    extensionModsBarByThreadID[selectedThreadID] = ExtensionModsBarState(
                        title: activeModsBarSlot.title ?? cachedThreadOutput.title,
                        markdown: cachedThreadOutput.markdown,
                        scope: cachedThreadOutput.scope ?? .thread,
                        actions: cachedThreadOutput.actions ?? [],
                        updatedAt: Date()
                    )
                } else {
                    extensionModsBarByThreadID.removeValue(forKey: selectedThreadID)
                }
            }

            if let selectedProjectID {
                let cachedProjectOutput = try await extensionStateStore.readModsBarOutput(
                    modDirectory: URL(fileURLWithPath: modDirectoryPath, isDirectory: true),
                    scope: .project,
                    threadID: nil,
                    projectID: selectedProjectID
                )
                if let cachedProjectOutput,
                   !cachedProjectOutput.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    extensionModsBarByProjectID[selectedProjectID] = ExtensionModsBarState(
                        title: activeModsBarSlot.title ?? cachedProjectOutput.title,
                        markdown: cachedProjectOutput.markdown,
                        scope: .project,
                        actions: cachedProjectOutput.actions ?? [],
                        updatedAt: Date()
                    )
                } else {
                    extensionModsBarByProjectID.removeValue(forKey: selectedProjectID)
                }
            }

            let cachedGlobalOutput = try await extensionStateStore.readModsBarOutput(
                modDirectory: URL(fileURLWithPath: modDirectoryPath, isDirectory: true),
                scope: .global,
                threadID: nil,
                projectID: nil
            )
            if let cachedGlobalOutput,
               !cachedGlobalOutput.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                extensionGlobalModsBarState = ExtensionModsBarState(
                    title: activeModsBarSlot.title ?? cachedGlobalOutput.title,
                    markdown: cachedGlobalOutput.markdown,
                    scope: .global,
                    actions: cachedGlobalOutput.actions ?? [],
                    updatedAt: Date()
                )
            } else {
                extensionGlobalModsBarState = nil
            }
        } catch {
            appendLog(.warning, "Failed to load extension modsBar cache: \(error.localizedDescription)")
        }
    }

    private func sanitizeExtensionLog(_ text: String) -> String {
        var sanitized = text
        let patterns = [
            "sk-[A-Za-z0-9_-]{20,}",
            "(?i)api[_-]?key\\s*[:=]\\s*[^\\s]+",
            "(?i)authorization\\s*:\\s*bearer\\s+[^\\s]+",
        ]
        for pattern in patterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
        return sanitized
    }

    private func configureBackgroundAutomationIfNeeded() async {
        let automationsRequiringBackground = activeExtensionAutomations.filter(\.definition.permissions.runWhenAppClosed)
        guard !automationsRequiringBackground.isEmpty else { return }

        let granted = await ensureBackgroundAutomationPermissionIfNeeded()
        guard granted else {
            extensionStatusMessage = "Background automations disabled by user preference."
            return
        }

        let launchdDirectory = storagePaths.systemURL
            .appendingPathComponent("launchd", isDirectory: true)
        let launchdManager = LaunchdManager()
        let uid = getuid()

        for automation in automationsRequiringBackground {
            let runWhenClosedPermission = ModExtensionPermissions(runWhenAppClosed: true)
            let permitted = await ensurePermissions(
                modID: automation.modID,
                permissions: runWhenClosedPermission,
                projectID: selectedProjectID,
                contextHint: "Background automation \(automation.definition.id)"
            )
            guard permitted else {
                await markAutomationState(
                    resolved: automation,
                    status: ExtensionAutomationStatus.launchdPermissionDenied,
                    error: "runWhenAppClosed permission denied",
                    nextRunAt: nil
                )
                continue
            }

            let label = launchdLabel(for: automation)
            let command = automation.definition.handler.command
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !command.isEmpty else {
                await markAutomationState(
                    resolved: automation,
                    status: ExtensionAutomationStatus.launchdFailed,
                    error: "Automation command is empty",
                    nextRunAt: nil
                )
                continue
            }

            let programArguments: [String] = if command[0].hasPrefix("/") {
                command
            } else {
                ["/usr/bin/env"] + command
            }
            let startInterval = launchdStartIntervalSeconds(for: automation.definition.schedule)
            let workingDirectory = launchdWorkingDirectoryPath(for: automation)
            let spec = LaunchdJobSpec(
                label: label,
                programArguments: programArguments,
                workingDirectory: workingDirectory,
                standardOutPath: launchdDirectory.appendingPathComponent("\(label).log").path,
                standardErrorPath: launchdDirectory.appendingPathComponent("\(label).err.log").path,
                startIntervalSeconds: startInterval
            )

            do {
                let plistURL = try launchdManager.writePlist(spec: spec, directoryURL: launchdDirectory)
                try? launchdManager.bootout(label: label, uid: uid)
                try launchdManager.bootstrap(plistURL: plistURL, uid: uid)

                let nextRun = try? CronSchedule(expression: automation.definition.schedule).nextRun(after: Date())
                await markAutomationState(
                    resolved: automation,
                    status: ExtensionAutomationStatus.launchdScheduled,
                    error: nil,
                    nextRunAt: nextRun
                )
            } catch {
                let details = Self.extensibilityProcessFailureDetails(from: error)
                let errorMessage = details?.summary ?? sanitizeExtensionLog(error.localizedDescription)
                if let details {
                    recordExtensibilityDiagnostic(surface: "launchd", operation: "configure", details: details)
                    appendLog(
                        .warning,
                        "Failed configuring launchd automation \(label) [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                    )
                } else {
                    appendLog(.warning, "Failed configuring launchd automation \(label): \(errorMessage)")
                }
                await markAutomationState(
                    resolved: automation,
                    status: ExtensionAutomationStatus.launchdFailed,
                    error: errorMessage,
                    nextRunAt: nil
                )
            }
        }
    }

    private func launchdWorkingDirectoryPath(for automation: ResolvedExtensionAutomation) -> String {
        if let cwd = automation.definition.handler.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cwd.isEmpty
        {
            return URL(fileURLWithPath: cwd, relativeTo: URL(fileURLWithPath: automation.modDirectoryPath, isDirectory: true))
                .standardizedFileURL
                .path
        }
        return automation.modDirectoryPath
    }

    private func launchdStartIntervalSeconds(for schedule: String) -> Int {
        guard let cron = try? CronSchedule(expression: schedule),
              let first = cron.nextRun(after: Date()),
              let second = cron.nextRun(after: first.addingTimeInterval(1))
        else {
            return 3600
        }
        let delta = Int(second.timeIntervalSince(first))
        return min(max(60, delta), 86400)
    }

    private func promptBookStateFileURL() -> URL? {
        guard let modDirectoryPath = promptBookModDirectoryPath() else { return nil }
        return URL(fileURLWithPath: modDirectoryPath, isDirectory: true)
            .appendingPathComponent(".codexchat/state/prompt-book.json", isDirectory: false)
    }

    private func promptBookModDirectoryPath() -> String? {
        if isPromptBookModsBarActiveForSelectedThread,
           let activeModsBarModDirectoryPath
        {
            return activeModsBarModDirectoryPath
        }
        if isLikelyPromptBookModID(activeModsBarModID),
           let activeModsBarModDirectoryPath
        {
            return activeModsBarModDirectoryPath
        }
        return activeExtensionHooks.first(where: { isLikelyPromptBookModID($0.modID) })?.modDirectoryPath
    }

    private func resolvedActiveModsBarActionHookID(preferredHookID: String) -> String? {
        guard let activeModID = normalizedActiveModsBarModID else {
            return nil
        }

        let actionHooks = activeExtensionHooks.filter {
            $0.modID == activeModID && $0.definition.event == .modsBarAction
        }
        guard !actionHooks.isEmpty else {
            return nil
        }

        if let preferred = actionHooks.first(where: { $0.definition.id == preferredHookID }) {
            return preferred.definition.id
        }
        if actionHooks.count == 1 {
            return actionHooks[0].definition.id
        }

        let preferredPrefix = preferredHookID.replacingOccurrences(of: "-action", with: "")
        if let prefixed = actionHooks.first(where: { $0.definition.id.hasPrefix(preferredPrefix) }) {
            return prefixed.definition.id
        }
        return actionHooks.first?.definition.id
    }

    private func resolvedActiveModsBarTargetModID(fallbackModID: String) -> String {
        normalizedActiveModsBarModID ?? fallbackModID
    }

    private var normalizedActiveModsBarModID: String? {
        let trimmed = (activeModsBarModID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func activeModsBarTitleContains(_ token: String) -> Bool {
        normalizedModsBarToken(activeModsBarSlot?.title).contains(token)
    }

    private func isLikelyPersonalNotesModID(_ modID: String?) -> Bool {
        let normalized = normalizedModsBarToken(modID)
        guard !normalized.isEmpty else { return false }
        return normalized == PersonalNotesModsBarConstants.canonicalModID || normalized.contains(PersonalNotesModsBarConstants.titleToken)
    }

    private func isLikelyPromptBookModID(_ modID: String?) -> Bool {
        let normalized = normalizedModsBarToken(modID)
        guard !normalized.isEmpty else { return false }
        return normalized == PromptBookModsBarConstants.canonicalModID || normalized.contains(PromptBookModsBarConstants.titleToken)
    }

    private func normalizedModsBarToken(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
    }

    private func rememberOpenPresentationMode(_ mode: ModsBarPresentationMode) {
        guard mode != .rail else { return }
        extensionModsBarLastOpenPresentationMode = mode
    }

    private func restoredOpenPresentationMode() -> ModsBarPresentationMode {
        let remembered = extensionModsBarLastOpenPresentationMode
        return remembered == .rail ? .peek : remembered
    }

    private func promptBookDefaultEntries() -> [PromptBookEntry] {
        normalizedPromptBookEntries([
            PromptBookEntry(
                id: "ship-checklist",
                title: "Ship Checklist",
                text: "Run our ship checklist for this branch: tests, docs, release notes, and rollout risks."
            ),
            PromptBookEntry(
                id: "risk-scan",
                title: "Risk Scan",
                text: "Review this diff for regressions, edge cases, and missing tests. Prioritize high-severity risks first."
            ),
        ])
    }

    private func normalizedPromptBookEntries(_ prompts: [PromptBookEntry]) -> [PromptBookEntry] {
        var normalized: [PromptBookEntry] = []
        for prompt in prompts {
            let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let titleCandidate = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = titleCandidate.isEmpty ? String(text.prefix(28)) : titleCandidate
            normalized.append(
                PromptBookEntry(
                    id: prompt.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString.lowercased() : prompt.id,
                    title: resolvedTitle,
                    text: text
                )
            )
            if normalized.count >= PromptBookModsBarConstants.maxPrompts {
                break
            }
        }
        return normalized
    }

    private func ensureBackgroundAutomationPermissionIfNeeded() async -> Bool {
        guard let preferenceRepository else { return false }

        do {
            if let existing = try await preferenceRepository.getPreference(key: .extensionsBackgroundAutomationPermission) {
                return existing == "allow"
            }

            let alert = NSAlert()
            alert.messageText = "Allow background automations?"
            alert.informativeText = "Extensions can run scheduled automations when CodexChat is closed. You can change this later in settings."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            let allowed = alert.runModal() == .alertFirstButtonReturn
            try await preferenceRepository.setPreference(
                key: .extensionsBackgroundAutomationPermission,
                value: allowed ? "allow" : "deny"
            )
            return allowed
        } catch {
            appendLog(.warning, "Failed to persist background automation preference: \(error.localizedDescription)")
            return false
        }
    }
}
