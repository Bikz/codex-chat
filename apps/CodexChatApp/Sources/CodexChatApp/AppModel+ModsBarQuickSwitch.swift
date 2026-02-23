import CodexMods
import Foundation

extension AppModel {
    var modsBarQuickSwitchOptions: [ModsBarQuickSwitchOption] {
        guard case let .loaded(surface) = modsState else { return [] }

        var options: [ModsBarQuickSwitchOption] = []

        let projectOptions = surface.projectMods
            .filter { $0.definition.uiSlots?.modsBar?.enabled == true }
            .map {
                ModsBarQuickSwitchOption(
                    scope: .project,
                    mod: $0,
                    isSelected: surface.selectedProjectModPath == $0.directoryPath
                )
            }

        let globalOptions = surface.globalMods
            .filter { $0.definition.uiSlots?.modsBar?.enabled == true }
            .map {
                ModsBarQuickSwitchOption(
                    scope: .global,
                    mod: $0,
                    isSelected: surface.selectedGlobalModPath == $0.directoryPath
                )
            }

        options.append(contentsOf: projectOptions)
        options.append(contentsOf: globalOptions)
        return options
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

    func modsBarQuickSwitchSymbolName(for option: ModsBarQuickSwitchOption) -> String {
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
        return "puzzlepiece.extension"
    }
}
