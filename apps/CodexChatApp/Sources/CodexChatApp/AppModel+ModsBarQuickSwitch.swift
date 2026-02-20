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
}
