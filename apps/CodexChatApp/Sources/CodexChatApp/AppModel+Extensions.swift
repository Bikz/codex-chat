import AppKit
import CodexChatCore
import CodexExtensions
import CodexMods
import Darwin
import Foundation

extension AppModel {
    func toggleExtensionInspector() {
        guard let selectedThreadID else { return }
        let next = !(extensionInspectorVisibilityByThreadID[selectedThreadID] ?? false)
        extensionInspectorVisibilityByThreadID[selectedThreadID] = next
        Task { try? await persistInspectorVisibilityPreference() }
    }

    func restoreExtensionInspectorVisibility() async {
        guard let preferenceRepository else { return }
        do {
            guard let raw = try await preferenceRepository.getPreference(key: .extensionsInspectorVisibilityByThread),
                  let data = raw.data(using: .utf8)
            else {
                extensionInspectorVisibilityByThreadID = [:]
                return
            }
            let decoded = try JSONDecoder().decode([String: Bool].self, from: data)
            extensionInspectorVisibilityByThreadID = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            })
        } catch {
            appendLog(.warning, "Failed to restore inspector visibility state: \(error.localizedDescription)")
        }
    }

    func persistInspectorVisibilityPreference() async throws {
        guard let preferenceRepository else { return }
        let raw = Dictionary(uniqueKeysWithValues: extensionInspectorVisibilityByThreadID.map { ($0.key.uuidString, $0.value) })
        let data = try JSONEncoder().encode(raw)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await preferenceRepository.setPreference(key: .extensionsInspectorVisibilityByThread, value: text)
    }

    func syncActiveExtensions(
        globalMods: [DiscoveredUIMod],
        projectMods: [DiscoveredUIMod],
        selectedGlobalPath: String?,
        selectedProjectPath: String?
    ) {
        let globalMod = globalMods.first(where: { $0.directoryPath == selectedGlobalPath })
        let projectMod = projectMods.first(where: { $0.directoryPath == selectedProjectPath })

        var hooks: [ResolvedExtensionHook] = []
        var automations: [ResolvedExtensionAutomation] = []

        if let globalMod {
            hooks.append(contentsOf: globalMod.definition.hooks.map {
                ResolvedExtensionHook(modID: globalMod.definition.manifest.id, modDirectoryPath: globalMod.directoryPath, definition: $0)
            })
            automations.append(contentsOf: globalMod.definition.automations.map {
                ResolvedExtensionAutomation(modID: globalMod.definition.manifest.id, modDirectoryPath: globalMod.directoryPath, definition: $0)
            })
        }

        if let projectMod {
            hooks.append(contentsOf: projectMod.definition.hooks.map {
                ResolvedExtensionHook(modID: projectMod.definition.manifest.id, modDirectoryPath: projectMod.directoryPath, definition: $0)
            })
            automations.append(contentsOf: projectMod.definition.automations.map {
                ResolvedExtensionAutomation(modID: projectMod.definition.manifest.id, modDirectoryPath: projectMod.directoryPath, definition: $0)
            })
        }

        activeExtensionHooks = hooks
        activeExtensionAutomations = automations

        if let projectInspector = projectMod?.definition.uiSlots?.rightInspector {
            activeRightInspectorSlot = projectInspector
        } else {
            activeRightInspectorSlot = globalMod?.definition.uiSlots?.rightInspector
        }

        if !(activeRightInspectorSlot?.enabled ?? false),
           let selectedThreadID
        {
            extensionInspectorVisibilityByThreadID[selectedThreadID] = false
        }

        Task {
            await refreshAutomationScheduler()
            await loadInspectorCacheForSelectedThread()
        }
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

    func refreshExtensionInspectorForSelectedThread() async {
        await loadInspectorCacheForSelectedThread()
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

    func extensionProjectContext(forThreadID threadID: UUID) -> (projectID: UUID, projectPath: String)? {
        if let activeTurnContext,
           activeTurnContext.localThreadID == threadID
        {
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

    func runHooks(for envelope: ExtensionEventEnvelope) async {
        guard !activeExtensionHooks.isEmpty else { return }

        let hooks = activeExtensionHooks.filter { $0.definition.event.rawValue == envelope.event.rawValue }
        guard !hooks.isEmpty else { return }

        for resolved in hooks {
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
                let errorMessage = sanitizeExtensionLog(error.localizedDescription)
                appendLog(.warning, "Extension hook \(resolved.definition.id) failed: \(errorMessage)")
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
            contextHint: "Automation \(resolved.definition.id)"
        )
        guard permissionOK else {
            await markAutomationState(
                resolved: resolved,
                status: "permission-denied",
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
            await markAutomationState(resolved: resolved, status: "ok", error: nil, nextRunAt: nextRun)
            return true
        } catch {
            let errorMessage = sanitizeExtensionLog(error.localizedDescription)
            await markAutomationState(resolved: resolved, status: "failed", error: errorMessage, nextRunAt: nil)
            appendLog(.warning, "Extension automation \(resolved.definition.id) failed: \(errorMessage)")
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

    private func ensurePermissions(
        modID: String,
        permissions: ModExtensionPermissions,
        contextHint: String
    ) async -> Bool {
        guard let extensionPermissionRepository else {
            return false
        }

        let requested = requestedCorePermissions(permissions)
        guard !requested.isEmpty else {
            return true
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

        if let inspector = output.inspector,
           let threadID = UUID(uuidString: envelope.thread.id),
           shouldApplyInspectorOutput(sourceHookID: sourceHookID)
        {
            let resolvedTitle = activeRightInspectorSlot?.title ?? inspector.title
            extensionInspectorByThreadID[threadID] = ExtensionInspectorState(
                title: resolvedTitle,
                markdown: inspector.markdown,
                updatedAt: Date()
            )
            do {
                _ = try await extensionStateStore.writeInspector(
                    markdown: inspector.markdown,
                    modDirectory: URL(fileURLWithPath: modDirectoryPath, isDirectory: true),
                    threadID: threadID
                )
            } catch {
                appendLog(.warning, "Failed to persist extension inspector output: \(error.localizedDescription)")
            }
        }

        if let artifacts = output.artifacts {
            applyArtifacts(artifacts, projectPath: envelope.project.path)
        }
    }

    private func applyArtifacts(_ artifacts: [ExtensionArtifactInstruction], projectPath: String) {
        let rootURL = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let fileManager = FileManager.default

        for artifact in artifacts {
            guard artifact.op == .upsert else { continue }
            let relative = artifact.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !relative.isEmpty else { continue }

            let destinationURL = URL(fileURLWithPath: relative, relativeTo: rootURL).standardizedFileURL
            let destinationPath = destinationURL.path
            guard destinationPath.hasPrefix(rootURL.path + "/") else {
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
        } catch {
            appendLog(.warning, "Failed to persist extension automation state: \(error.localizedDescription)")
        }
    }

    private func launchdLabel(for resolved: ResolvedExtensionAutomation) -> String {
        let safeMod = resolved.modID.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
        let safeAutomation = resolved.definition.id.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
        return "app.codexchat.\(safeMod).\(safeAutomation)"
    }

    private func shouldApplyInspectorOutput(sourceHookID: String?) -> Bool {
        guard let slot = activeRightInspectorSlot,
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

    private func loadInspectorCacheForSelectedThread() async {
        guard let selectedThreadID,
              let activeRightInspectorSlot,
              activeRightInspectorSlot.enabled
        else {
            return
        }

        let hookID = activeRightInspectorSlot.source?.hookID
        let modDirectoryPath: String? = if let hookID {
            activeExtensionHooks.first(where: { $0.definition.id == hookID })?.modDirectoryPath
        } else {
            activeExtensionHooks.first?.modDirectoryPath
        }

        guard let modDirectoryPath else { return }

        do {
            let cached = try await extensionStateStore.readInspector(
                modDirectory: URL(fileURLWithPath: modDirectoryPath, isDirectory: true),
                threadID: selectedThreadID
            )
            if let cached, !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extensionInspectorByThreadID[selectedThreadID] = ExtensionInspectorState(
                    title: activeRightInspectorSlot.title,
                    markdown: cached,
                    updatedAt: Date()
                )
            }
        } catch {
            appendLog(.warning, "Failed to load extension inspector cache: \(error.localizedDescription)")
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
                contextHint: "Background automation \(automation.definition.id)"
            )
            guard permitted else {
                await markAutomationState(
                    resolved: automation,
                    status: "permission-denied",
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
                    status: "failed",
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
                    status: "scheduled",
                    error: nil,
                    nextRunAt: nextRun
                )
            } catch {
                let errorMessage = sanitizeExtensionLog(error.localizedDescription)
                appendLog(.warning, "Failed configuring launchd automation \(label): \(errorMessage)")
                await markAutomationState(
                    resolved: automation,
                    status: "failed",
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
