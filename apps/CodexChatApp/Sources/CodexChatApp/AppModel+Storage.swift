import AppKit
import Foundation

struct StorageRootMigrationResult {
    let oldPaths: CodexChatStoragePaths
    let newPaths: CodexChatStoragePaths
}

extension AppModel {
    func applyStartupStorageFixups() async throws {
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

            if let projectSkillEnablementRepository {
                try await projectSkillEnablementRepository.rewriteSkillPaths(
                    projectID: project.id,
                    fromRootPath: oldRootPath,
                    toRootPath: newRootPath
                )
            }
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
}
