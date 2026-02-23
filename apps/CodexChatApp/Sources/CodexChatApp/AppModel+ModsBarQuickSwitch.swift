import CodexMods
import Foundation

extension AppModel {
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

    func modsBarQuickSwitchSymbolName(for option: ModsBarQuickSwitchOption) -> String {
        if let explicit = option.mod.definition.manifest.iconSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return explicit
        }

        let title = modsBarQuickSwitchTitle(for: option).lowercased()
        let id = option.mod.definition.manifest.id.lowercased()

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
