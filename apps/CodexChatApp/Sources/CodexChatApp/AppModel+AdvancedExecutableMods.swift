import CodexChatCore
import CodexMods
import Foundation

extension AppModel {
    func restoreAdvancedExecutableModsUnlockIfNeeded() async {
        guard let preferenceRepository else {
            areAdvancedExecutableModsUnlocked = false
            return
        }

        do {
            let migrationKey = AppPreferenceKey.advancedExecutableModsMigrationV1
            let unlockKey = AppPreferenceKey.advancedExecutableModsUnlock

            let alreadyMigrated = try await preferenceRepository.getPreference(key: migrationKey) == "1"
            if alreadyMigrated {
                let value = try await preferenceRepository.getPreference(key: unlockKey)
                areAdvancedExecutableModsUnlocked = value == "allow"
                return
            }

            let hasExistingSignals = try await detectExistingModUserSignals()
            let defaultValue = hasExistingSignals ? "allow" : "deny"
            try await preferenceRepository.setPreference(key: unlockKey, value: defaultValue)
            try await preferenceRepository.setPreference(key: migrationKey, value: "1")
            areAdvancedExecutableModsUnlocked = defaultValue == "allow"

            appendLog(
                .info,
                hasExistingSignals
                    ? "Preserved legacy executable mod behavior for existing install."
                    : "Defaulted advanced executable mods to locked for new install."
            )
        } catch {
            areAdvancedExecutableModsUnlocked = false
            appendLog(.warning, "Failed restoring advanced executable mods unlock: \(error.localizedDescription)")
        }
    }

    func setAdvancedExecutableModsUnlocked(_ unlocked: Bool) {
        guard let preferenceRepository else {
            areAdvancedExecutableModsUnlocked = unlocked
            return
        }

        Task {
            do {
                try await preferenceRepository.setPreference(
                    key: .advancedExecutableModsUnlock,
                    value: unlocked ? "allow" : "deny"
                )
                areAdvancedExecutableModsUnlocked = unlocked
                modStatusMessage = unlocked
                    ? "Advanced executable mods are unlocked."
                    : "Advanced executable mods are locked."
            } catch {
                modStatusMessage = "Failed to update advanced mods unlock: \(error.localizedDescription)"
                appendLog(.error, "Failed updating advanced mods unlock: \(error.localizedDescription)")
            }
        }
    }

    func canRunExecutableModFeatures(for mod: DiscoveredUIMod) -> Bool {
        guard modHasExecutableFeatures(mod) else {
            return true
        }

        if isVettedFirstPartyMod(mod) {
            return true
        }

        return areAdvancedExecutableModsUnlocked
    }

    func executableModBlockedReason(for mod: DiscoveredUIMod) -> String? {
        guard modHasExecutableFeatures(mod),
              !isVettedFirstPartyMod(mod),
              !areAdvancedExecutableModsUnlocked
        else {
            return nil
        }

        return "This mod includes executable hooks/automations. Unlock advanced executable mods in Settings > Experimental to enable it."
    }

    func modHasExecutableFeatures(_ mod: DiscoveredUIMod) -> Bool {
        !mod.definition.hooks.isEmpty || !mod.definition.automations.isEmpty
    }

    private func detectExistingModUserSignals() async throws -> Bool {
        if let extensionInstallRepository {
            let installs = try await extensionInstallRepository.list()
            if !installs.isEmpty {
                return true
            }
        }

        if case let .loaded(surface) = modsState,
           surface.selectedGlobalModPath != nil || surface.selectedProjectModPath != nil
        {
            return true
        }

        return projects.contains(where: { ($0.uiModPath ?? "").isEmpty == false })
    }

    private func isVettedFirstPartyMod(_ mod: DiscoveredUIMod) -> Bool {
        let id = mod.definition.manifest.id.lowercased()
        if id.hasPrefix("codexchat.") {
            return true
        }

        let normalizedPath = NSString(string: mod.directoryPath).standardizingPath
        return normalizedPath.contains("/mods/first-party/")
    }
}
