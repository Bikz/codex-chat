import CodexChatCore
@testable import CodexChatShared
import CodexMods
import CodexSkills
import XCTest

final class SkillsModsPresentationTests: XCTestCase {
    func testFilteredSkillsMatchesNameDescriptionAndScopeCaseInsensitive() {
        let browser = makeSkillItem(
            name: "Agent Browser",
            description: "Automates browser interactions for web workflows.",
            scope: .global,
            path: "/tmp/skills/agent-browser"
        )
        let deploy = makeSkillItem(
            name: "Cloudflare Deploy",
            description: "Deploy Workers and Pages applications.",
            scope: .project,
            path: "/tmp/skills/cloudflare-deploy"
        )

        let byName = SkillsModsPresentation.filteredSkills([browser, deploy], query: "browser")
        XCTAssertEqual(byName.map(\.id), [browser.id])

        let byDescription = SkillsModsPresentation.filteredSkills([browser, deploy], query: "workers")
        XCTAssertEqual(byDescription.map(\.id), [deploy.id])

        let byScope = SkillsModsPresentation.filteredSkills([browser, deploy], query: "GLOBAL")
        XCTAssertEqual(byScope.map(\.id), [browser.id])
    }

    func testFilteredSkillsWhitespaceQueryReturnsAllInOriginalOrder() {
        let first = makeSkillItem(
            name: "Analytics",
            description: "Track events.",
            scope: .project,
            path: "/tmp/skills/analytics"
        )
        let second = makeSkillItem(
            name: "Build Things",
            description: "Utility helpers.",
            scope: .global,
            path: "/tmp/skills/build-things"
        )

        let filtered = SkillsModsPresentation.filteredSkills([first, second], query: "   ")
        XCTAssertEqual(filtered.map(\.id), [first.id, second.id])
    }

    func testFilteredSkillsNoMatchReturnsEmpty() {
        let items = [
            makeSkillItem(name: "Atlas", description: "Control Atlas app.", scope: .global, path: "/tmp/skills/atlas"),
            makeSkillItem(name: "Biome", description: "Lint and format.", scope: .project, path: "/tmp/skills/biome"),
        ]

        XCTAssertTrue(SkillsModsPresentation.filteredSkills(items, query: "does-not-exist").isEmpty)
    }

    func testModDirectoryNameUsesLastPathComponent() {
        let mod = makeMod(path: "/tmp/mods/Solarized")
        XCTAssertEqual(SkillsModsPresentation.modDirectoryName(mod), "Solarized")
    }

    func testModDirectoryNameFallbackForEmptyPath() {
        let mod = makeMod(path: "   ")
        XCTAssertEqual(SkillsModsPresentation.modDirectoryName(mod), "(unknown)")
    }

    func testModStatusThemeOnlyForSchemaV1WithoutExtensions() {
        let mod = makeMod(path: "/tmp/mods/ThemeOnly")
        XCTAssertEqual(SkillsModsPresentation.modStatus(mod), .themeOnly)
        XCTAssertEqual(SkillsModsPresentation.modCapabilities(mod), [.theme])
    }

    func testModStatusExtensionEnabledForHooks() {
        let mod = makeMod(
            path: "/tmp/mods/Hooked",
            definition: makeDefinition(
                schemaVersion: 1,
                hooks: [
                    ModHookDefinition(
                        id: "turn-summary",
                        event: .turnCompleted,
                        handler: ModExtensionHandler(command: ["node", "hook.js"])
                    ),
                ]
            )
        )

        XCTAssertEqual(SkillsModsPresentation.modStatus(mod), .extensionEnabled)
        XCTAssertEqual(SkillsModsPresentation.modCapabilities(mod), [.theme, .hooks, .privileged])
    }

    func testModCapabilitiesIncludeAutomationsAndModsBar() {
        let mod = makeMod(
            path: "/tmp/mods/AutoInspect",
            definition: makeDefinition(
                schemaVersion: 1,
                automations: [
                    ModAutomationDefinition(
                        id: "daily-notes",
                        schedule: "0 9 * * *",
                        handler: ModExtensionHandler(command: ["python3", "automation.py"])
                    ),
                ],
                uiSlots: ModUISlots(
                    modsBar: .init(
                        enabled: true,
                        title: "Summary",
                        source: .init(type: "handlerOutput", hookID: "turn-summary")
                    )
                )
            )
        )

        XCTAssertEqual(SkillsModsPresentation.modStatus(mod), .extensionEnabled)
        XCTAssertEqual(
            SkillsModsPresentation.modCapabilities(mod),
            [.theme, .automations, .modsBar, .privileged]
        )
    }

    func testModCapabilitiesDoNotIncludeDisabledModsBarSlot() {
        let mod = makeMod(
            path: "/tmp/mods/DisabledModsBar",
            definition: makeDefinition(
                schemaVersion: 1,
                uiSlots: ModUISlots(
                    modsBar: .init(
                        enabled: false,
                        title: "Disabled"
                    )
                )
            )
        )

        XCTAssertEqual(SkillsModsPresentation.modStatus(mod), .themeOnly)
        XCTAssertEqual(SkillsModsPresentation.modCapabilities(mod), [.theme])
    }

    func testModsBarHelpTextVariesByActiveModsBarSource() {
        XCTAssertEqual(
            SkillsModsPresentation.modsBarHelpText(hasActiveModsBarSource: true),
            "Mods bar content comes from the active mod. Hidden by default, and opens automatically when new modsBar output arrives."
        )
        XCTAssertEqual(
            SkillsModsPresentation.modsBarHelpText(hasActiveModsBarSource: false),
            "No active modsBar mod. Install one in Skills & Mods > Mods."
        )
    }

    func testInstallModDescriptionCallsOutAutoEnableAndPermissions() {
        XCTAssertTrue(SkillsModsPresentation.installModDescription.localizedCaseInsensitiveContains("github"))
        XCTAssertTrue(SkillsModsPresentation.installModDescription.localizedCaseInsensitiveContains("review"))
        XCTAssertTrue(SkillsModsPresentation.installModDescription.localizedCaseInsensitiveContains("permission-gated"))
    }

    func testModArchetypesCoverDiscoverabilitySurface() {
        let titles = SkillsModsPresentation.modArchetypes.map(\.title)
        XCTAssertEqual(
            titles,
            ["Theme Packs", "Turn/Thread Hooks", "Scheduled Automations", "Right Mods bar Panels"]
        )
    }

    func testUpdateActionLabelMapping() {
        XCTAssertEqual(SkillsModsPresentation.updateActionLabel(for: .gitUpdate), "Update")
        XCTAssertEqual(SkillsModsPresentation.updateActionLabel(for: .reinstall), "Reinstall")
        XCTAssertEqual(SkillsModsPresentation.updateActionLabel(for: .unavailable), "Unavailable")
    }

    func testEnabledTargetsSummaryIncludesProjectContextSuffix() {
        var item = makeSkillItem(
            name: "Atlas",
            description: "Control Atlas app.",
            scope: .global,
            path: "/tmp/skills/atlas"
        )
        item.enabledTargets = [.global, .project]

        XCTAssertEqual(
            SkillsModsPresentation.enabledTargetsSummary(for: item, hasSelectedProject: true),
            "Enabled in: Global, Project (this)"
        )
    }

    private func makeSkillItem(
        name: String,
        description: String,
        scope: SkillScope,
        path: String
    ) -> AppModel.SkillListItem {
        let skill = DiscoveredSkill(
            name: name,
            description: description,
            scope: scope,
            skillPath: path,
            skillDefinitionPath: "\(path)/SKILL.md",
            hasScripts: false,
            sourceURL: nil,
            optionalMetadata: [:]
        )
        return AppModel.SkillListItem(
            skill: skill,
            enabledTargets: [.project],
            isEnabledForSelectedProject: true,
            updateCapability: .unavailable,
            updateSource: nil,
            updateInstaller: nil
        )
    }

    private func makeMod(path: String, definition: UIModDefinition? = nil) -> DiscoveredUIMod {
        let manifest = UIModManifest(id: UUID().uuidString, name: "Test Mod", version: "1.0.0")
        let resolvedDefinition = definition ?? UIModDefinition(schemaVersion: 1, manifest: manifest, theme: ModThemeOverride())
        return DiscoveredUIMod(
            scope: .global,
            directoryPath: path,
            definitionPath: "\(path)/ui.mod.json",
            definition: resolvedDefinition,
            computedChecksum: nil
        )
    }

    private func makeDefinition(
        schemaVersion: Int = 1,
        hooks: [ModHookDefinition] = [],
        automations: [ModAutomationDefinition] = [],
        uiSlots: ModUISlots? = nil
    ) -> UIModDefinition {
        UIModDefinition(
            schemaVersion: schemaVersion,
            manifest: UIModManifest(id: UUID().uuidString, name: "Test Mod", version: "1.0.0"),
            theme: ModThemeOverride(),
            hooks: hooks,
            automations: automations,
            uiSlots: uiSlots
        )
    }
}
