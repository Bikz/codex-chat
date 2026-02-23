import CodexMods
import Foundation

extension AppModel {
    private enum ModsBarIconOverridesStorage {
        static func normalized(_ raw: [String: String]) -> [String: String] {
            var normalized: [String: String] = [:]
            for (modID, symbol) in raw {
                let cleanID = modID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanID.isEmpty, !cleanSymbol.isEmpty else { continue }
                normalized[cleanID] = cleanSymbol
            }
            return normalized
        }
    }

    var modsBarQuickSwitchOptions: [ModsBarQuickSwitchOption] {
        guard case let .loaded(surface) = modsState else { return [] }

        var candidates: [ModsBarQuickSwitchOption] = []

        let projectOptions = surface.projectMods
            .filter {
                $0.definition.uiSlots?.modsBar?.enabled == true
                    && surface.enabledProjectModIDs.contains($0.definition.manifest.id)
            }
            .map {
                ModsBarQuickSwitchOption(
                    scope: .project,
                    mod: $0,
                    isSelected: surface.selectedProjectModPath == $0.directoryPath
                )
            }

        let globalOptions = surface.globalMods
            .filter {
                $0.definition.uiSlots?.modsBar?.enabled == true
                    && surface.enabledGlobalModIDs.contains($0.definition.manifest.id)
            }
            .map {
                ModsBarQuickSwitchOption(
                    scope: .global,
                    mod: $0,
                    isSelected: surface.selectedGlobalModPath == $0.directoryPath
                )
            }

        candidates.append(contentsOf: projectOptions)
        candidates.append(contentsOf: globalOptions)

        var deduped: [ModsBarQuickSwitchOption] = []
        var indexByModID: [String: Int] = [:]

        for option in candidates {
            let modID = option.mod.definition.manifest.id.lowercased()
            if let existingIndex = indexByModID[modID] {
                if !deduped[existingIndex].isSelected, option.isSelected {
                    deduped[existingIndex] = option
                }
                continue
            }
            indexByModID[modID] = deduped.count
            deduped.append(option)
        }

        return deduped
    }

    var hasModsBarQuickSwitchChoices: Bool {
        modsBarQuickSwitchOptions.count > 1
    }

    var modsBarQuickSwitchSections: [ModsBarQuickSwitchSection] {
        let grouped = Dictionary(grouping: modsBarQuickSwitchOptions, by: \.scope)
        let orderedScopes: [ModsBarQuickSwitchOption.Scope] = [.project, .global]
        return orderedScopes.compactMap { scope in
            guard let options = grouped[scope], !options.isEmpty else { return nil }
            return ModsBarQuickSwitchSection(scope: scope, options: options)
        }
    }

    var selectedModsBarQuickSwitchOption: ModsBarQuickSwitchOption? {
        modsBarQuickSwitchOptions.first(where: \.isSelected)
    }

    func modsBarIconPresetSymbols() -> [String] {
        [
            "puzzlepiece.extension",
            "text.book.closed",
            "note.text",
            "text.alignleft",
            "bookmark",
            "wand.and.stars",
            "square.and.pencil",
            "tray.full",
            "doc.on.doc",
            "magnifyingglass",
            "sparkles",
            "list.bullet.rectangle",
            "slider.horizontal.3",
            "calendar",
            "checklist",
            "shield.lefthalf.filled",
        ]
    }

    func activateModsBarQuickSwitchOption(_ option: ModsBarQuickSwitchOption) {
        switch option.scope {
        case .global:
            setGlobalMod(option.mod)
        case .project:
            setProjectMod(option.mod)
        }
    }

    func modsBarQuickSwitchTitle(for option: ModsBarQuickSwitchOption) -> String {
        let explicitTitle = option.mod.definition.uiSlots?.modsBar?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitTitle, !explicitTitle.isEmpty {
            return explicitTitle
        }
        return option.mod.definition.manifest.name
    }

    func modsBarQuickSwitchTooltip(for option: ModsBarQuickSwitchOption) -> String {
        "\(modsBarQuickSwitchTitle(for: option)) (\(option.scope.label))"
    }

    func setModsBarIconOverride(modID: String, symbolName: String?) {
        let normalizedModID = modID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModID.isEmpty else { return }
        var next = modsBarIconOverridesByModID
        if let symbolName {
            let normalizedSymbol = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedSymbol.isEmpty {
                next.removeValue(forKey: normalizedModID)
            } else {
                next[normalizedModID] = normalizedSymbol
            }
        } else {
            next.removeValue(forKey: normalizedModID)
        }
        modsBarIconOverridesByModID = next
        persistModsBarIconOverrides()
    }

    func restoreModsBarIconOverridesIfNeeded() async {
        guard let preferenceRepository else { return }
        do {
            guard let raw = try await preferenceRepository.getPreference(key: .modsBarIconOverridesV1),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                modsBarIconOverridesByModID = [:]
                return
            }
            modsBarIconOverridesByModID = ModsBarIconOverridesStorage.normalized(decoded)
        } catch {
            appendLog(.warning, "Failed restoring mods bar icon overrides: \(error.localizedDescription)")
        }
    }

    private func persistModsBarIconOverrides() {
        guard let preferenceRepository else { return }
        let snapshot = ModsBarIconOverridesStorage.normalized(modsBarIconOverridesByModID)
        modsBarIconOverridesPersistenceTask?.cancel()
        modsBarIconOverridesPersistenceTask = Task { [weak self] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                let value = String(data: data, encoding: .utf8) ?? "{}"
                try await preferenceRepository.setPreference(key: .modsBarIconOverridesV1, value: value)
            } catch {
                self?.appendLog(.warning, "Failed persisting mods bar icon overrides: \(error.localizedDescription)")
            }
        }
    }

    func modsBarQuickSwitchSymbolName(for option: ModsBarQuickSwitchOption) -> String {
        let modID = option.mod.definition.manifest.id.lowercased()
        if let override = modsBarIconOverridesByModID[modID],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return override
        }

        if let explicit = option.mod.definition.manifest.iconSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return explicit
        }

        let title = modsBarQuickSwitchTitle(for: option).lowercased()
        let id = modID

        if title.contains("prompt") || id.contains("prompt") {
            return "text.book.closed"
        }
        if title.contains("note") || id.contains("note") {
            return "note.text"
        }
        if title.contains("calendar") || id.contains("calendar") {
            return "calendar"
        }
        if title.contains("risk") || id.contains("risk") {
            return "shield.lefthalf.filled"
        }
        if title.contains("ship") || id.contains("ship") {
            return "checklist"
        }
        if title.contains("summary") || id.contains("summary") {
            return "text.alignleft"
        }

        let fallbackSymbols = [
            "puzzlepiece.extension",
            "bookmark",
            "wand.and.stars",
            "square.and.pencil",
            "tray.full",
            "doc.on.doc",
            "magnifyingglass",
            "sparkles",
            "list.bullet.rectangle",
            "slider.horizontal.3",
        ]
        let seed = id.unicodeScalars.reduce(0) { partial, scalar in
            ((partial &* 33) &+ Int(scalar.value)) & 0x7fffffff
        }
        return fallbackSymbols[seed % fallbackSymbols.count]
    }
}
