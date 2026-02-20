@testable import CodexChatShared
import CodexKit
import CodexSkills
import XCTest

@MainActor
final class ComposerSkillAutocompleteTests: XCTestCase {
    func testComposerSkillAutocompleteShowsAllSkillsForDollarToken() {
        let model = makeReadyModel()
        let enabled = makeSkillItem(
            name: "macos-calendar-assistant",
            description: "Calendar help.",
            enabled: true
        )
        let disabled = makeSkillItem(
            name: "agent-browser",
            description: "Web automation.",
            enabled: false
        )
        model.skillsState = .loaded([disabled, enabled])
        model.composerText = "$"

        XCTAssertTrue(model.isComposerSkillAutocompleteActive)
        XCTAssertEqual(model.composerSkillAutocompleteSuggestions.map(\.id), [enabled.id, disabled.id])
    }

    func testComposerSkillAutocompleteNarrowsAsQueryGrows() {
        let model = makeReadyModel()
        let desktop = makeSkillItem(
            name: "macos-desktop-cleanup",
            description: "Desktop cleanup.",
            enabled: true
        )
        let messages = makeSkillItem(
            name: "macos-send-message",
            description: "Send a message.",
            enabled: true
        )
        model.skillsState = .loaded([desktop, messages])
        model.composerText = "$desk"

        XCTAssertEqual(model.composerSkillAutocompleteSuggestions.map(\.id), [desktop.id])
    }

    func testApplyComposerSkillAutocompleteSuggestionReplacesTrailingToken() {
        let model = makeReadyModel()
        let desktop = makeSkillItem(
            name: "macos-desktop-cleanup",
            description: "Desktop cleanup.",
            enabled: true
        )
        model.skillsState = .loaded([desktop])
        model.composerText = "Please use $desk"

        model.applyComposerSkillAutocompleteSuggestion(desktop)

        XCTAssertEqual(model.composerText, "Please use $macos-desktop-cleanup ")
        XCTAssertEqual(model.selectedSkillIDForComposer, desktop.id)
    }

    func testApplyComposerSkillAutocompleteSuggestionDisabledSkillAutoEnablesAndSelects() {
        let model = makeReadyModel()
        let enabled = makeSkillItem(
            name: "macos-calendar-assistant",
            description: "Calendar help.",
            enabled: true
        )
        let disabled = makeSkillItem(
            name: "macos-send-message",
            description: "Send a message.",
            enabled: false
        )
        model.skillsState = .loaded([enabled, disabled])
        model.selectedSkillIDForComposer = enabled.id
        model.composerText = "$msg"

        model.applyComposerSkillAutocompleteSuggestion(disabled)

        XCTAssertEqual(model.composerText, "$macos-send-message ")
        XCTAssertEqual(model.selectedSkillIDForComposer, disabled.id)
        XCTAssertNil(model.skillStatusMessage)
        XCTAssertEqual(model.selectedSkillForComposer?.id, disabled.id)
    }

    func testComposerSkillAutocompleteInactiveWithoutTrailingToken() {
        let model = makeReadyModel()
        model.composerText = "Use this skill $macos-calendar-assistant please"

        XCTAssertFalse(model.isComposerSkillAutocompleteActive)
        XCTAssertTrue(model.composerSkillAutocompleteSuggestions.isEmpty)
    }

    private func makeReadyModel() -> AppModel {
        let model = AppModel(
            repositories: nil,
            runtime: CodexRuntime(executableResolver: { nil }),
            bootError: nil
        )
        model.selectedProjectID = UUID()
        model.selectedThreadID = UUID()
        return model
    }

    private func makeSkillItem(
        name: String,
        description: String,
        enabled: Bool
    ) -> AppModel.SkillListItem {
        let path = "/tmp/skills/\(name)"
        let skill = DiscoveredSkill(
            name: name,
            description: description,
            scope: .project,
            skillPath: path,
            skillDefinitionPath: "\(path)/SKILL.md",
            hasScripts: false,
            sourceURL: nil,
            optionalMetadata: [:]
        )
        return AppModel.SkillListItem(
            skill: skill,
            enabledTargets: enabled ? [.project] : [],
            isEnabledForSelectedProject: enabled,
            updateCapability: .unavailable,
            updateSource: nil,
            updateInstaller: nil
        )
    }
}
