@testable import CodexChatShared
import XCTest

final class CodexChatCLICommandParserTests: XCTestCase {
    func testParsesDoctorAndSmokeCommands() throws {
        XCTAssertEqual(try CodexChatCLICommandParser.parse(arguments: ["doctor"]), .doctor)
        XCTAssertEqual(try CodexChatCLICommandParser.parse(arguments: ["smoke"]), .smoke)
    }

    func testParsesReproWithFixtureAndOverrideRoot() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: ["repro", "--fixture", "basic-turn", "--fixtures-root", "/tmp/fixtures"]
        )

        XCTAssertEqual(
            command,
            .repro(
                CodexChatCLIReproOptions(
                    fixtureName: "basic-turn",
                    fixturesRootOverride: "/tmp/fixtures"
                )
            )
        )
    }

    func testParsesModValidateAndInspectSource() throws {
        let validate = try CodexChatCLICommandParser.parse(
            arguments: ["mod", "validate", "--source", "/tmp/mod"]
        )
        XCTAssertEqual(validate, .mod(.validate(source: "/tmp/mod")))

        let inspect = try CodexChatCLICommandParser.parse(
            arguments: ["mod", "inspect-source", "https://github.com/acme/repo/tree/main/mods/prompt-book"]
        )
        XCTAssertEqual(
            inspect,
            .mod(.inspectSource(source: "https://github.com/acme/repo/tree/main/mods/prompt-book"))
        )
    }

    func testParsesModInitWithDefaultOutput() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: ["mod", "init", "--name", "Prompt Book"],
            currentDirectoryPath: "/tmp/current"
        )

        XCTAssertEqual(
            command,
            .mod(.initSample(name: "Prompt Book", outputPath: "/tmp/current"))
        )
    }

    func testParsesModInitWithExplicitOutput() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: ["mod", "init", "--name", "Prompt Book", "--output", "/tmp/mods"],
            currentDirectoryPath: "/tmp/current"
        )

        XCTAssertEqual(
            command,
            .mod(.initSample(name: "Prompt Book", outputPath: "/tmp/mods"))
        )
    }

    func testRejectsInvalidModArguments() throws {
        XCTAssertThrowsError(try CodexChatCLICommandParser.parse(arguments: ["mod"])) { error in
            XCTAssertEqual(
                (error as? CodexChatCLIArgumentError)?.message,
                "`mod` requires a subcommand: init, validate, or inspect-source"
            )
        }

        XCTAssertThrowsError(try CodexChatCLICommandParser.parse(arguments: ["mod", "init", "--name"])) { error in
            XCTAssertEqual(
                (error as? CodexChatCLIArgumentError)?.message,
                "Missing value for --name"
            )
        }
    }
}
