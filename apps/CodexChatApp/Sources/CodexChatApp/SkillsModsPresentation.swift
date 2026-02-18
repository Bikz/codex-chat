import CodexMods
import Foundation

enum SkillsModsPresentation {
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
}
