import CodexMods
import Foundation

enum SkillsModsPresentation {
    struct ModArchetype: Hashable {
        let title: String
        let detail: String
    }

    enum ModCapability: String, CaseIterable {
        case theme = "Theme"
        case hooks = "Hooks"
        case automations = "Automations"
        case inspector = "Inspector"
    }

    enum ModExtensionStatus: String {
        case themeOnly = "Theme-only"
        case extensionEnabled = "Extension-enabled"
    }

    static let extensionExperimentalBadge = "Experimental API (schemaVersion: 2)"
    static let installModDescription = """
    Install from a git URL or a local folder containing `ui.mod.json`. Installed mods are enabled immediately. \
    Privileged hook or automation actions are permission-gated and prompted on first use.
    """
    static let inspectorToolbarHelp = """
    Inspector content comes from the active mod. Hidden by default, and opens automatically when new inspector output arrives.
    """
    static let inspectorToolbarEmptyHelp = "No active inspector mod. Install one in Skills & Mods > Mods."
    static let modArchetypes: [ModArchetype] = [
        .init(title: "Theme Packs", detail: "Visual token overrides (`schemaVersion: 1/2`)."),
        .init(title: "Turn/Thread Hooks", detail: "Event-driven summaries and side effects."),
        .init(title: "Scheduled Automations", detail: "Cron jobs for notes and log sync workflows."),
        .init(title: "Right Inspector Panels", detail: "Toggleable inspector content, collapsed by default."),
    ]

    static func filteredSkills(_ items: [AppModel.SkillListItem], query: String) -> [AppModel.SkillListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter { item in
            item.skill.name.localizedCaseInsensitiveContains(trimmed)
                || item.skill.description.localizedCaseInsensitiveContains(trimmed)
                || item.skill.scope.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func modDirectoryName(_ mod: DiscoveredUIMod) -> String {
        let path = mod.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "(unknown)" }

        let normalized = NSString(string: path).standardizingPath
        let last = URL(fileURLWithPath: normalized).lastPathComponent
        return last.isEmpty ? normalized : last
    }

    static func modCapabilities(_ mod: DiscoveredUIMod) -> [ModCapability] {
        var capabilities: [ModCapability] = [.theme]

        if !mod.definition.hooks.isEmpty {
            capabilities.append(.hooks)
        }
        if !mod.definition.automations.isEmpty {
            capabilities.append(.automations)
        }
        if mod.definition.uiSlots?.rightInspector?.enabled == true {
            capabilities.append(.inspector)
        }

        return capabilities
    }

    static func modStatus(_ mod: DiscoveredUIMod) -> ModExtensionStatus {
        hasExtensionFeatures(mod.definition) ? .extensionEnabled : .themeOnly
    }

    static func inspectorHelpText(hasActiveInspectorSource: Bool) -> String {
        hasActiveInspectorSource ? inspectorToolbarHelp : inspectorToolbarEmptyHelp
    }

    private static func hasExtensionFeatures(_ definition: UIModDefinition) -> Bool {
        !definition.hooks.isEmpty
            || !definition.automations.isEmpty
            || definition.uiSlots?.rightInspector?.enabled == true
    }
}
