@testable import CodexChatShared
import Foundation
import XCTest

final class CodexRoleProfileBuilderTests: XCTestCase {
    func testBuildUpdatesProfilesAndAgentsWithAbsoluteConfigPath() throws {
        let codexHome = try makeTempDirectory(prefix: "role-builder")
        let input = CodexRoleProfileBuilderInput(
            profileName: "developer-fast",
            profileModel: "gpt-5.3-codex",
            profileReasoningEffort: "high",
            profileReasoningSummary: "detailed",
            profileVerbosity: "high",
            profilePersonality: "pragmatic",
            roleName: "backend_arch",
            roleDescription: "Designs backend modules and boundaries.",
            roleConfigFilename: "backend_arch.toml",
            roleDeveloperInstructions: "Focus on modular, testable backend architecture."
        )

        let output = try CodexRoleProfileBuilder.build(
            input: input,
            root: .object([:]),
            codexHomeURL: codexHome
        )

        XCTAssertEqual(
            output.updatedRoot.value(at: [.key("profiles"), .key("developer-fast"), .key("model")])?.stringValue,
            "gpt-5.3-codex"
        )
        XCTAssertEqual(
            output.updatedRoot.value(at: [.key("agents"), .key("backend_arch"), .key("description")])?.stringValue,
            "Designs backend modules and boundaries."
        )

        let configPath = output.updatedRoot.value(at: [.key("agents"), .key("backend_arch"), .key("config_file")])?.stringValue
        XCTAssertEqual(configPath, codexHome.appendingPathComponent("agents/backend_arch.toml", isDirectory: false).path)
        XCTAssertTrue(output.roleConfigContents.contains("developer_instructions"))
    }

    func testBuildNormalizesNamesAndRoleFilename() throws {
        let codexHome = try makeTempDirectory(prefix: "role-builder-sanitize")
        let input = CodexRoleProfileBuilderInput(
            profileName: " Mobile App Profile ",
            profileModel: "gpt-5.3-codex",
            profileReasoningEffort: "medium",
            profileReasoningSummary: "concise",
            profileVerbosity: "medium",
            profilePersonality: "balanced",
            roleName: "Frontend Architect!",
            roleDescription: "Frontend architecture guidance.",
            roleConfigFilename: "../unsafe/path/frontend",
            roleDeveloperInstructions: "Build scalable frontend systems."
        )

        let output = try CodexRoleProfileBuilder.build(
            input: input,
            root: .object([:]),
            codexHomeURL: codexHome
        )

        XCTAssertEqual(output.normalizedProfileName, "mobile_app_profile")
        XCTAssertEqual(output.normalizedRoleName, "frontend_architect")
        XCTAssertTrue(output.roleConfigPath.hasSuffix("/agents/frontend.toml"))
    }

    func testWriteRoleTemplateCreatesAgentsDirectory() throws {
        let codexHome = try makeTempDirectory(prefix: "role-builder-write")
        let configPath = codexHome.appendingPathComponent("agents/test_role.toml", isDirectory: false).path
        let contents = "model = \"gpt-5.3-codex\"\n"

        try CodexRoleProfileBuilder.writeRoleTemplate(contents: contents, to: configPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))
        XCTAssertEqual(try String(contentsOfFile: configPath), contents)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
