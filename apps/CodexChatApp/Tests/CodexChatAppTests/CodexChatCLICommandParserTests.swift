@testable import CodexChatShared
import XCTest

final class CodexChatCLICommandParserTests: XCTestCase {
    func testParsesDoctorAndSmokeCommands() throws {
        XCTAssertEqual(try CodexChatCLICommandParser.parse(arguments: ["doctor"]), .doctor)
        XCTAssertEqual(try CodexChatCLICommandParser.parse(arguments: ["smoke"]), .smoke)
    }

    func testParsesReplayCommandWithJSONAndLimit() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: [
                "replay",
                "--project-path",
                "/tmp/project",
                "--thread-id",
                "00000000-0000-0000-0000-000000000111",
                "--limit",
                "25",
                "--json",
            ]
        )

        XCTAssertEqual(
            command,
            .replay(
                CodexChatCLIReplayOptions(
                    projectPath: "/tmp/project",
                    threadID: "00000000-0000-0000-0000-000000000111",
                    limit: 25,
                    asJSON: true
                )
            )
        )
    }

    func testParsesLedgerExportCommand() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: [
                "ledger",
                "export",
                "--project-path",
                "/tmp/project",
                "--thread-id",
                "00000000-0000-0000-0000-000000000222",
                "--limit",
                "10",
                "--output",
                "/tmp/ledger.json",
            ]
        )

        XCTAssertEqual(
            command,
            .ledger(
                .export(
                    CodexChatCLILedgerExportOptions(
                        projectPath: "/tmp/project",
                        threadID: "00000000-0000-0000-0000-000000000222",
                        limit: 10,
                        outputPath: "/tmp/ledger.json"
                    )
                )
            )
        )
    }

    func testParsesLedgerBackfillCommand() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: [
                "ledger",
                "backfill",
                "--project-path",
                "/tmp/project",
                "--limit",
                "50",
                "--force",
                "--json",
            ]
        )

        XCTAssertEqual(
            command,
            .ledger(
                .backfill(
                    CodexChatCLILedgerBackfillOptions(
                        projectPath: "/tmp/project",
                        limit: 50,
                        force: true,
                        asJSON: true
                    )
                )
            )
        )
    }

    func testParsesLedgerBackfillCommandWithDefaultOptions() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: [
                "ledger",
                "backfill",
                "--project-path",
                "/tmp/project",
            ]
        )

        XCTAssertEqual(
            command,
            .ledger(
                .backfill(
                    CodexChatCLILedgerBackfillOptions(
                        projectPath: "/tmp/project",
                        limit: .max,
                        force: false,
                        asJSON: false
                    )
                )
            )
        )
    }

    func testParsesPolicyValidateCommand() throws {
        let command = try CodexChatCLICommandParser.parse(
            arguments: ["policy", "validate", "--file", "/tmp/policy.json"]
        )

        XCTAssertEqual(
            command,
            .policy(.validate(CodexChatCLIPolicyValidateOptions(filePath: "/tmp/policy.json")))
        )
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

    func testRejectsInvalidReplayAndLedgerArguments() throws {
        XCTAssertThrowsError(try CodexChatCLICommandParser.parse(arguments: ["replay", "--project-path", "/tmp/p"])) { error in
            XCTAssertEqual(
                (error as? CodexChatCLIArgumentError)?.message,
                "`replay` requires --thread-id <uuid>"
            )
        }

        XCTAssertThrowsError(
            try CodexChatCLICommandParser.parse(arguments: [
                "ledger",
                "export",
                "--project-path",
                "/tmp/p",
                "--thread-id",
                "id",
                "--limit",
                "0",
            ])
        ) { error in
            XCTAssertEqual(
                (error as? CodexChatCLIArgumentError)?.message,
                "--limit must be a positive integer"
            )
        }

        XCTAssertThrowsError(
            try CodexChatCLICommandParser.parse(arguments: [
                "ledger",
                "backfill",
                "--limit",
                "10",
            ])
        ) { error in
            XCTAssertEqual(
                (error as? CodexChatCLIArgumentError)?.message,
                "`ledger backfill` requires --project-path <path>"
            )
        }
    }
}
