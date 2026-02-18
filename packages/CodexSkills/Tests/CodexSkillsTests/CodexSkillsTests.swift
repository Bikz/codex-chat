import XCTest
@testable import CodexSkills

final class CodexSkillsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexSkillsPackage.version, "0.1.0")
    }

    func testDiscoverSkillsScansProjectAndGlobalScopes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let agentsHome = root.appendingPathComponent(".agents", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)

        try createSkill(
            at: codexHome.appendingPathComponent("skills/global-skill", isDirectory: true),
            body: """
            ---
            name: global-skill
            description: Global skill description
            ---
            # Global Skill
            """
        )

        try createSkill(
            at: project.appendingPathComponent(".agents/skills/project-skill", isDirectory: true),
            body: """
            # Project Skill

            Project skill description.
            """,
            includeScripts: true
        )

        let service = SkillCatalogService(
            codexHomeURL: codexHome,
            agentsHomeURL: agentsHome
        )

        let discovered = try service.discoverSkills(projectPath: project.path)
        XCTAssertEqual(discovered.count, 2)

        let global = discovered.first(where: { $0.name == "global-skill" })
        XCTAssertEqual(global?.scope, .global)
        XCTAssertEqual(global?.description, "Global skill description")
        XCTAssertFalse(global?.hasScripts ?? true)

        let projectSkill = discovered.first(where: { $0.name == "Project Skill" })
        XCTAssertEqual(projectSkill?.scope, .project)
        XCTAssertEqual(projectSkill?.description, "Project skill description.")
        XCTAssertTrue(projectSkill?.hasScripts ?? false)
    }

    func testTrustedSourceDetection() {
        let service = SkillCatalogService(
            processRunner: { _, _ in "" }
        )

        XCTAssertTrue(service.isTrustedSource("https://github.com/openai/example-skill"))
        XCTAssertTrue(service.isTrustedSource("/tmp/local-skill"))
        XCTAssertFalse(service.isTrustedSource("https://unknown.example.com/skill"))
        XCTAssertFalse(service.isTrustedSource("git@unknown.example.com:owner/skill.git"))
    }

    private func createSkill(at directoryURL: URL, body: String, includeScripts: Bool = false) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let skillFile = directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
        try body.write(to: skillFile, atomically: true, encoding: .utf8)
        if includeScripts {
            try FileManager.default.createDirectory(
                at: directoryURL.appendingPathComponent("scripts", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }
}
