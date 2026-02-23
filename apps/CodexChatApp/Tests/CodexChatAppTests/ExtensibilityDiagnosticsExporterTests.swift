@testable import CodexChatShared
import XCTest

@MainActor
final class ExtensibilityDiagnosticsExporterTests: XCTestCase {
    func testPayloadDataIncludesRetentionAndEvents() throws {
        let snapshot = ExtensibilityDiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            retentionLimit: 150,
            events: [
                .init(
                    timestamp: Date(timeIntervalSince1970: 1_700_000_001),
                    surface: "extensions",
                    operation: "hook",
                    kind: "timeout",
                    command: "extension-worker",
                    summary: "Timed out after 500ms."
                ),
            ]
        )

        let data = try ExtensibilityDiagnosticsExporter.payloadData(snapshot: snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExtensibilityDiagnosticsSnapshot.self, from: data)

        XCTAssertEqual(decoded.retentionLimit, 150)
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events[0].surface, "extensions")
        XCTAssertEqual(decoded.events[0].operation, "hook")
        XCTAssertEqual(decoded.events[0].kind, "timeout")
    }
}
