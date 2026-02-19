import CodexChatCore
import CodexMods
import CodexSkills
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
        case modsBar = "Mods bar"
    }

    enum ModExtensionStatus: String {
        case themeOnly = "Theme-only"
        case extensionEnabled = "Extension-enabled"
    }

    static let extensionExperimentalBadge = "Extension API (schemaVersion: 1)"
    static let installModDescription = """
    Install from a GitHub URL or a local folder containing `ui.mod.json`. Review package metadata and permissions before install. \
    Privileged hook or automation actions are permission-gated and prompted on first use.
    """
    static let modsBarToolbarHelp = """
    Mods bar content comes from the active mod. Hidden by default, and opens automatically when new modsBar output arrives.
    """
    static let modsBarToolbarEmptyHelp = "No active modsBar mod. Install one in Skills & Mods > Mods."
    static let skillsSectionDescription = "Installed skills are shown first. Available skills from skills.sh are listed below."
    static let modArchetypes: [ModArchetype] = [
        .init(title: "Theme Packs", detail: "Visual token overrides (`schemaVersion: 1`)."),
        .init(title: "Turn/Thread Hooks", detail: "Event-driven summaries and side effects."),
        .init(title: "Scheduled Automations", detail: "Cron jobs for notes and log sync workflows."),
        .init(title: "Right Mods bar Panels", detail: "Toggleable modsBar content, collapsed by default."),
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

    static func filteredCatalogSkills(_ items: [CatalogSkillListing], query: String) -> [CatalogSkillListing] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmed)
                || item.summary?.localizedCaseInsensitiveContains(trimmed) == true
                || item.repositoryURL?.localizedCaseInsensitiveContains(trimmed) == true
        }
    }

    static func availableCatalogSkills(
        from catalog: [CatalogSkillListing],
        installedSkills: [AppModel.SkillListItem]
    ) -> [CatalogSkillListing] {
        let installedIDs = Set(installedSkills.compactMap { $0.skill.optionalMetadata["id"]?.lowercased() })
        let installedRepos = Set(installedSkills.compactMap { ($0.skill.installMetadata?.source ?? $0.skill.sourceURL)?.lowercased() })
        let installedNames = Set(installedSkills.map { $0.skill.name.lowercased() })

        return catalog.filter { listing in
            let listingID = listing.id.lowercased()
            if installedIDs.contains(listingID) {
                return false
            }
            if let repo = (listing.installSource ?? listing.repositoryURL)?.lowercased(),
               installedRepos.contains(repo)
            {
                return false
            }
            if installedNames.contains(listing.name.lowercased()) {
                return false
            }
            return true
        }
    }

    static func updateActionLabel(for capability: SkillUpdateCapability) -> String {
        switch capability {
        case .gitUpdate:
            "Update"
        case .reinstall:
            "Reinstall"
        case .unavailable:
            "Unavailable"
        }
    }

    static func updateActionHelp(for capability: SkillUpdateCapability) -> String {
        switch capability {
        case .gitUpdate:
            "Pull latest changes from git."
        case .reinstall:
            "Reinstall this skill from its install source."
        case .unavailable:
            "No source metadata available for update."
        }
    }

    static func enabledTargetsSummary(for item: AppModel.SkillListItem, hasSelectedProject: Bool) -> String {
        var labels: [String] = []
        if item.isEnabledGlobally {
            labels.append("Global")
        }
        if item.isEnabledForGeneral {
            labels.append("General")
        }
        if item.isEnabledForProjectTarget {
            labels.append(hasSelectedProject ? "Project (this)" : "Project")
        }

        guard !labels.isEmpty else {
            return "Enabled in: None"
        }
        return "Enabled in: \(labels.joined(separator: ", "))"
    }

    static func scopeLabel(for target: SkillEnablementTarget) -> String {
        switch target {
        case .global:
            "Global"
        case .general:
            "General"
        case .project:
            "Project"
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
        if mod.definition.uiSlots?.modsBar?.enabled == true {
            capabilities.append(.modsBar)
        }

        return capabilities
    }

    static func modStatus(_ mod: DiscoveredUIMod) -> ModExtensionStatus {
        hasExtensionFeatures(mod.definition) ? .extensionEnabled : .themeOnly
    }

    static func modsBarHelpText(hasActiveModsBarSource: Bool) -> String {
        hasActiveModsBarSource ? modsBarToolbarHelp : modsBarToolbarEmptyHelp
    }

    private static func hasExtensionFeatures(_ definition: UIModDefinition) -> Bool {
        !definition.hooks.isEmpty
            || !definition.automations.isEmpty
            || definition.uiSlots?.modsBar?.enabled == true
    }
}
