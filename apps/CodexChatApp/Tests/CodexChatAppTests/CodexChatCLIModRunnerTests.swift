@testable import CodexChatShared
import Foundation
import XCTest

final class CodexChatCLIModRunnerTests: XCTestCase {
    func testInitValidateAndInspectRoundTrip() throws {
        let root = try makeTempDirectory(prefix: "cli-mod-runner")
        defer { try? FileManager.default.removeItem(at: root) }

        let initResult = try CodexChatCLIModRunner.run(
            command: .initSample(name: "CLI Runner Mod", outputPath: root.path)
        )
        XCTAssertEqual(initResult.stdoutLines.first, "Created sample mod package:")
        XCTAssertTrue(initResult.stderrLines.isEmpty)

        let modRoot = try XCTUnwrap(initResult.stdoutLines.dropFirst().first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: modRoot + "/codex.mod.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modRoot + "/ui.mod.json"))

        let validateResult = try CodexChatCLIModRunner.run(command: .validate(source: modRoot))
        XCTAssertTrue(validateResult.stdoutLines.contains("Mod package is valid."))
        XCTAssertTrue(validateResult.stdoutLines.contains("id: cli-runner-mod"))
        XCTAssertTrue(validateResult.stderrLines.isEmpty)

        let inspectResult = try CodexChatCLIModRunner.run(command: .inspectSource(source: modRoot))
        XCTAssertEqual(inspectResult.stdoutLines.count, 1)
        XCTAssertTrue(inspectResult.stderrLines.isEmpty)

        let inspectData = Data(inspectResult.stdoutLines[0].utf8)
        let payload = try JSONDecoder().decode(CodexChatCLIModInspectPayload.self, from: inspectData)
        XCTAssertEqual(payload.id, "cli-runner-mod")
        XCTAssertEqual(payload.manifestSource, "codexManifest")
        XCTAssertEqual(payload.ui.hookCount, 1)
        XCTAssertEqual(payload.ui.automationCount, 1)
        XCTAssertTrue(payload.ui.hasModsBarSlot)
    }

    func testValidateMissingSourceThrowsDeterministicError() {
        XCTAssertThrowsError(
            try CodexChatCLIModRunner.run(command: .validate(source: "/tmp/codexchat-does-not-exist"))
        ) { error in
            let message = (error as NSError).localizedDescription.lowercased()
            XCTAssertTrue(message.contains("not found") || message.contains("source"))
        }
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let url = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
