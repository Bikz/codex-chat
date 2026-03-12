import AppKit
import Foundation

struct StorageRootMigrationResult {
    let oldPaths: CodexChatStoragePaths
    let newPaths: CodexChatStoragePaths
}

extension AppModel {
    func applyStartupStorageFixups() async throws {
        await runSharedCodexHomeHandoffIfNeeded()
        refreshSharedHomeStorageState()

        guard let projectRepository else {
            return
        }

        if let general = projects.first(where: \.isGeneralProject) {
            let canonicalGeneralPath = storagePaths.generalProjectURL.path
            if general.path != canonicalGeneralPath {
                try migrateLegacyGeneralProjectIfNeeded(from: general.path, to: canonicalGeneralPath)
                _ = try await projectRepository.updateProjectPath(id: general.id, path: canonicalGeneralPath)
                try await prepareProjectFolderStructure(projectPath: canonicalGeneralPath)
                appendLog(.info, "Updated General project path to canonical storage root.")
            }
        }

        if let preferenceRepository,
           let legacyRoot = try? CodexChatStoragePaths.legacyAppSupportRootURL()
        {
            let legacyGlobalModsRoot = legacyRoot
                .appendingPathComponent("Mods", isDirectory: true)
                .appendingPathComponent("Global", isDirectory: true)
                .standardizedFileURL
                .path

            if let currentGlobalModPath = try await preferenceRepository.getPreference(key: .globalUIModPath),
               currentGlobalModPath.hasPrefix(legacyGlobalModsRoot)
            {
                let suffix = String(currentGlobalModPath.dropFirst(legacyGlobalModsRoot.count))
                let normalizedSuffix = suffix.hasPrefix("/") ? suffix : "/\(suffix)"
                let updated = storagePaths.globalModsURL.path + normalizedSuffix
                try await preferenceRepository.setPreference(key: .globalUIModPath, value: updated)
                appendLog(.info, "Rewrote legacy global mod path into the active storage root.")
            }
        }

        try await refreshProjects()
        await migrateLegacyChatArchivesIfNeeded()
    }

    func changeStorageRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose CodexChat Root"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let selectedURL = panel.url
        else {
            return
        }

        Task {
            await applyStorageRootChange(to: selectedURL.standardizedFileURL)
        }
    }

    func revealStorageRoot() {
        NSWorkspace.shared.activateFileViewerSelecting([storagePaths.rootURL])
    }

    func revealActiveCodexHome() {
        NSWorkspace.shared.activateFileViewerSelecting([resolvedCodexHomes.activeCodexHomeURL])
    }

    func revealActiveAgentsHome() {
        NSWorkspace.shared.activateFileViewerSelecting([resolvedCodexHomes.activeAgentsHomeURL])
    }

    func archiveLegacyManagedHomes() {
        guard !isLegacyManagedHomesArchiveInProgress else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await runLegacyManagedHomesArchiveFlow()
        }
    }

    func revealLastLegacyManagedHomesArchive() {
        guard let report = try? CodexChatStorageMigrationCoordinator.readLastLegacyManagedHomesArchiveReport(paths: storagePaths),
              let archivePath = report.archiveRootPath,
              !archivePath.isEmpty
        else {
            storageStatusMessage = "No legacy managed-home archive is currently available."
            return
        }

        let archiveURL = URL(fileURLWithPath: archivePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            storageStatusMessage = "Last legacy managed-home archive no longer exists on disk."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
    }

    private func applyStorageRootChange(to newRootURL: URL) async {
        do {
            let result = try await migrateStorageRoot(to: newRootURL)
            storageStatusMessage = "Storage root moved to \(result.newPaths.rootURL.path). Restarting is required."
            appendLog(.info, "Storage root changed from \(result.oldPaths.rootURL.path) to \(result.newPaths.rootURL.path)")
            showRestartRequiredAlert(oldRootURL: result.oldPaths.rootURL)
        } catch {
            storageStatusMessage = "Failed to change storage root: \(error.localizedDescription)"
            appendLog(.error, "Storage root change failed: \(error.localizedDescription)")
        }
    }

    func migrateStorageRoot(to newRootURL: URL) async throws -> StorageRootMigrationResult {
        let oldPaths = storagePaths
        let newPaths = CodexChatStoragePaths(rootURL: newRootURL)

        try CodexChatStorageMigrationCoordinator.validateRootSelection(
            newRootURL: newPaths.rootURL,
            currentRootURL: oldPaths.rootURL
        )

        let unexpected = try CodexChatStorageMigrationCoordinator.unexpectedTopLevelEntries(in: newPaths.rootURL)
        if !unexpected.isEmpty, !confirmRootCollision(entries: unexpected) {
            throw CodexChatStorageMigrationError.invalidRootSelection("Storage root change cancelled by user.")
        }

        try newPaths.ensureRootStructure()
        try CodexChatStorageMigrationCoordinator.migrateManagedRoot(from: oldPaths, to: newPaths)

        try await rewriteMetadataForManagedRootChange(oldPaths: oldPaths, newPaths: newPaths)
        try CodexChatStorageMigrationCoordinator.syncSQLiteFiles(
            sourceSQLiteURL: oldPaths.metadataDatabaseURL,
            destinationSQLiteURL: newPaths.metadataDatabaseURL,
            overwriteExisting: true
        )

        CodexChatStoragePaths.persistRootURL(newPaths.rootURL)
        storageRootPath = newPaths.rootURL.path
        return StorageRootMigrationResult(oldPaths: oldPaths, newPaths: newPaths)
    }

    func rewriteMetadataForManagedRootChange(
        oldPaths: CodexChatStoragePaths,
        newPaths: CodexChatStoragePaths
    ) async throws {
        guard let projectRepository
        else {
            return
        }

        try await refreshProjects()
        let oldRootPath = oldPaths.rootURL.path
        let newRootPath = newPaths.rootURL.path

        for project in projects {
            guard CodexChatStoragePaths.isPath(project.path, insideRoot: oldRootPath) else {
                continue
            }

            let suffix = String(project.path.dropFirst(oldRootPath.count))
            let newPath = (newRootPath + suffix).replacingOccurrences(of: "//", with: "/")
            if newPath != project.path {
                _ = try await projectRepository.updateProjectPath(id: project.id, path: newPath)
            }

            if let existingProjectModPath = project.uiModPath,
               existingProjectModPath.hasPrefix(oldRootPath)
            {
                let modSuffix = String(existingProjectModPath.dropFirst(oldRootPath.count))
                let rewrittenModPath = (newRootPath + modSuffix).replacingOccurrences(of: "//", with: "/")
                if rewrittenModPath != existingProjectModPath {
                    _ = try await projectRepository.updateProjectUIModPath(id: project.id, uiModPath: rewrittenModPath)
                }
            }
        }

        if let projectSkillEnablementRepository {
            try await projectSkillEnablementRepository.rewriteSkillPaths(
                fromRootPath: oldRootPath,
                toRootPath: newRootPath
            )
        }

        if let preferenceRepository {
            if let globalModPath = try await preferenceRepository.getPreference(key: .globalUIModPath),
               globalModPath.hasPrefix(oldPaths.globalModsURL.path)
            {
                let suffix = String(globalModPath.dropFirst(oldPaths.globalModsURL.path.count))
                let normalizedSuffix = suffix.hasPrefix("/") ? suffix : "/\(suffix)"
                try await preferenceRepository.setPreference(
                    key: .globalUIModPath,
                    value: newPaths.globalModsURL.path + normalizedSuffix
                )
            }
        }

        try await refreshProjects()
    }

    private func migrateLegacyGeneralProjectIfNeeded(from sourcePath: String, to destinationPath: String) throws {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true).standardizedFileURL
        let destinationURL = URL(fileURLWithPath: destinationPath, isDirectory: true).standardizedFileURL

        guard sourceURL.path != destinationURL.path else {
            return
        }

        if !fileManager.fileExists(atPath: sourceURL.path) {
            return
        }

        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        }

        if let children = try? fileManager.contentsOfDirectory(atPath: destinationURL.path), children.isEmpty {
            try fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private func confirmRootCollision(entries: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Selected root contains existing files"
        let preview = entries.prefix(5).joined(separator: ", ")
        alert.informativeText = """
        The folder has existing content (\(preview)). Continue only if you want CodexChat to use this location.
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showRestartRequiredAlert(oldRootURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "CodexChat moved your managed storage root. The app will now close so it can reopen with the new root."
        alert.addButton(withTitle: "Close App")
        _ = alert.runModal()

        do {
            try CodexChatStorageMigrationCoordinator.deleteRootIfExists(oldRootURL)
        } catch {
            appendLog(.warning, "Failed to remove old storage root at \(oldRootURL.path): \(error.localizedDescription)")
        }

        NSApp.terminate(nil)
    }

    private func runSharedCodexHomeHandoffIfNeeded() async {
        do {
            let result = try CodexChatStorageMigrationCoordinator.performSharedHomeHandoffIfNeeded(
                paths: storagePaths,
                homes: resolvedCodexHomes
            )
            applySharedCodexHomeHandoffResult(result)
        } catch {
            storageStatusMessage = "Shared Codex home handoff warning: \(error.localizedDescription)"
            appendLog(.warning, "Shared Codex home handoff failed: \(error.localizedDescription)")
            refreshSharedHomeStorageState()
        }
    }

    private func applySharedCodexHomeHandoffResult(_ result: SharedCodexHomeHandoffResult) {
        if result.executed {
            if !result.copiedEntries.isEmpty {
                storageStatusMessage = "Imported \(result.copiedEntries.count) legacy managed-home artifact(s) into the shared Codex homes."
                appendLog(
                    .info,
                    "Shared Codex home handoff copied \(result.copiedEntries.count) artifact(s) into active shared homes."
                )
            } else if result.failedEntries.isEmpty {
                appendLog(.debug, "Shared Codex home handoff completed with no missing artifacts to import.")
            } else {
                storageStatusMessage = "Shared Codex home handoff completed with warnings. See logs for details."
            }

            if !result.failedEntries.isEmpty {
                for failure in result.failedEntries {
                    appendLog(.warning, "Shared Codex home handoff warning: \(failure)")
                }
            }
        }

        refreshSharedHomeStorageState()
    }

    private func runLegacyManagedHomesArchiveFlow() async {
        isLegacyManagedHomesArchiveInProgress = true
        storageStatusMessage = "Archiving legacy managed CodexChat home copies…"
        defer {
            isLegacyManagedHomesArchiveInProgress = false
        }

        do {
            let result = try CodexChatStorageMigrationCoordinator.archiveLegacyManagedHomes(paths: storagePaths)
            if result.executed, let archiveRootURL = result.archiveRootURL {
                storageStatusMessage = "Archived legacy managed homes to \(archiveRootURL.path)."
                appendLog(.info, "Archived legacy managed homes to \(archiveRootURL.path)")
            } else if result.failedEntries.isEmpty {
                storageStatusMessage = "No legacy managed home copies were available to archive."
            } else {
                storageStatusMessage = "Legacy managed-home archive completed with warnings. See logs for details."
            }

            for failure in result.failedEntries {
                appendLog(.warning, "Legacy managed-home archive warning: \(failure)")
            }
        } catch {
            storageStatusMessage = "Legacy managed-home archive failed: \(error.localizedDescription)"
            appendLog(.warning, "Legacy managed-home archive failed: \(error.localizedDescription)")
        }

        refreshSharedHomeStorageState()
    }

    func refreshSharedHomeStorageState() {
        do {
            lastSharedCodexHomeHandoffReportPath =
                try CodexChatStorageMigrationCoordinator.readLastSharedCodexHomeHandoffReport(paths: storagePaths) == nil ?
                nil :
                storagePaths.sharedCodexHomeHandoffReportURL.path
            lastLegacyManagedHomesArchivePath =
                try CodexChatStorageMigrationCoordinator.readLastLegacyManagedHomesArchiveReport(paths: storagePaths)?
                    .archiveRootPath
        } catch {
            lastSharedCodexHomeHandoffReportPath = nil
            lastLegacyManagedHomesArchivePath = nil
            appendLog(.warning, "Failed to load shared-home storage report: \(error.localizedDescription)")
        }
    }

    private func migrateLegacyChatArchivesIfNeeded() async {
        for project in projects {
            guard Self.projectDirectoryExists(path: project.path) else {
                continue
            }

            do {
                let migratedCount = try ChatArchiveStore.migrateLegacyDateShardedArchivesIfNeeded(
                    projectPath: project.path
                )
                if migratedCount > 0 {
                    appendLog(
                        .info,
                        "Backfilled \(migratedCount) legacy chat turn(s) into canonical transcripts for \(project.name)."
                    )
                }
            } catch {
                appendLog(
                    .warning,
                    "Legacy chat archive backfill failed for \(project.name): \(error.localizedDescription)"
                )
            }
        }
    }
}
