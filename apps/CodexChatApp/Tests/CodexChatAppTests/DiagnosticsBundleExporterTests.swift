@testable import CodexChatShared
import CodexKit
import XCTest

final class DiagnosticsBundleExporterTests: XCTestCase {
    func testDiagnosticsBundleSnapshotEncodesRuntimeHandshake() throws {
        let handshake = RuntimeHandshake(
            clientInfo: RuntimeClientInfo(
                name: "codexchat_app",
                title: "CodexChat",
                version: "1.2.3"
            ),
            sentCapabilities: RuntimeClientCapabilities(
                experimentalAPI: false,
                optOutNotificationMethods: ["experimental/ignored"]
            ),
            negotiatedCapabilities: RuntimeCapabilities(
                supportsTurnSteer: true,
                supportsFollowUpSuggestions: true,
                supportsServerRequestResolution: true
            ),
            runtimeVersion: RuntimeVersionInfo(
                rawValue: "0.114.0",
                major: 0,
                minor: 114,
                patch: 0
            ),
            compatibility: RuntimeCompatibilityState(
                detectedVersion: RuntimeVersionInfo(
                    rawValue: "0.114.0",
                    major: 0,
                    minor: 114,
                    patch: 0
                ),
                supportLevel: .validated,
                supportedMinorLine: "0.114",
                graceMinorLine: "0.113",
                degradedReasons: [],
                disabledFeatures: []
            )
        )

        let snapshot = DiagnosticsBundleSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            runtimeStatus: .connected,
            runtimeIssue: nil,
            runtimeHandshake: handshake,
            accountSummary: "Signed in",
            approvalStatusMessage: "Approval sent",
            serverRequestStatusMessage: "Runtime request answered",
            pendingRuntimeRequests: [
                RuntimeRequestSupportSummary(
                    requestID: "17",
                    kind: .permissionsApproval,
                    threadID: "thread-1",
                    title: "Permission request pending",
                    summary: "Need project.write",
                    responseOptions: [
                        RuntimeRequestSupportAction(id: "grant", label: "Grant"),
                        RuntimeRequestSupportAction(id: "decline", label: "Decline"),
                    ],
                    permissions: ["project.write"],
                    options: [],
                    scopeHint: "workspace",
                    toolName: nil,
                    serverName: nil
                ),
            ],
            runtimeRequestSupportEvents: [
                RuntimeRequestSupportEvent(
                    id: UUID(),
                    timestamp: Date(timeIntervalSince1970: 1_700_000_050),
                    phase: .requested,
                    requestID: "17",
                    kind: .permissionsApproval,
                    threadID: "thread-1",
                    title: "Permission request pending",
                    summary: "Need project.write"
                ),
            ],
            logs: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticsBundleSnapshot.self, from: data)

        XCTAssertEqual(decoded.runtimeHandshake?.runtimeVersion?.rawValue, "0.114.0")
        XCTAssertEqual(decoded.runtimeHandshake?.compatibility.supportLevel, .validated)
        XCTAssertEqual(decoded.runtimeHandshake?.negotiatedCapabilities.supportsServerRequestResolution, true)
        XCTAssertEqual(decoded.runtimeHandshake?.sentCapabilities.optOutNotificationMethods, ["experimental/ignored"])
        XCTAssertEqual(decoded.pendingRuntimeRequests.first?.permissions, ["project.write"])
        XCTAssertEqual(decoded.runtimeRequestSupportEvents.first?.phase, .requested)
    }
}
