@testable import CodexChatShared
import CodexKit
import CodexSkills
import XCTest

final class SkillReferenceResolverTests: XCTestCase {
    func testParserFindsTokenAtEndOfMessage() {
        let tokens = SkillReferenceParser.referencedTokens(in: "Please use $agent-browser")
        XCTAssertEqual(tokens, ["agent-browser"])
    }

    func testParserFindsTokenMidText() {
        let tokens = SkillReferenceParser.referencedTokens(in: "Use $agent-browser for this task please")
        XCTAssertEqual(tokens, ["agent-browser"])
    }

    func testParserFindsMultipleUniqueTokensInOrder() {
        let tokens = SkillReferenceParser.referencedTokens(
            in: "Use $agent-browser then $macos-send-message and $agent-browser again"
        )
        XCTAssertEqual(tokens, ["agent-browser", "macos-send-message"])
    }

    func testParserStopsAtInvalidCharacter() {
        let tokens = SkillReferenceParser.referencedTokens(in: "Try $agent-browser! now")
        XCTAssertEqual(tokens, ["agent-browser"])
    }

    func testResolutionMatchesCaseInsensitively() {
        let inputs = SkillReferenceResolver.runtimeSkillInputs(
            messageText: "Run $AGENT-BROWSER please",
            availableSkills: [makeSkillItem(name: "agent-browser")]
        )
        XCTAssertEqual(inputs, [RuntimeSkillInput(name: "agent-browser", path: "/tmp/skills/agent-browser")])
    }

    func testResolutionSupportsDashAliasForSkillsWithSpaces() {
        let inputs = SkillReferenceResolver.runtimeSkillInputs(
            messageText: "Need $atlas-tool now",
            availableSkills: [makeSkillItem(name: "Atlas Tool", path: "/tmp/skills/atlas-tool")]
        )
        XCTAssertEqual(inputs, [RuntimeSkillInput(name: "Atlas Tool", path: "/tmp/skills/atlas-tool")])
    }

    func testResolutionIgnoresUnknownSkillsSafely() {
        let inputs = SkillReferenceResolver.runtimeSkillInputs(
            messageText: "Use $unknown and $agent-browser",
            availableSkills: [makeSkillItem(name: "agent-browser")]
        )
        XCTAssertEqual(inputs, [RuntimeSkillInput(name: "agent-browser", path: "/tmp/skills/agent-browser")])
    }

    private func makeSkillItem(name: String, path: String? = nil) -> AppModel.SkillListItem {
        let skillPath = path ?? "/tmp/skills/\(name)"
        let skill = DiscoveredSkill(
            name: name,
            description: "Test skill.",
            scope: .project,
            skillPath: skillPath,
            skillDefinitionPath: "\(skillPath)/SKILL.md",
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
}
