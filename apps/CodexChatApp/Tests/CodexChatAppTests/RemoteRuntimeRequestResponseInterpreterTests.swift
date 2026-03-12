import CodexChatRemoteControl
@testable import CodexChatShared
import CodexKit
import XCTest

final class RemoteRuntimeRequestResponseInterpreterTests: XCTestCase {
    func testPermissionsDeclineBeatsAccidentalGrantPayload() throws {
        let request = RuntimePermissionsRequest(
            id: 1,
            method: "item/permissions/requestApproval",
            threadID: "thread-1",
            turnID: nil,
            itemID: nil,
            reason: "Need write access",
            cwd: "/tmp",
            permissions: ["project.write"],
            grantRoot: "workspace",
            detail: "Need project.write"
        )

        let response = try RemoteRuntimeRequestResponseInterpreter.permissionsResponse(
            for: request,
            payload: RemoteControlRuntimeRequestResponse(
                permissions: ["project.write"],
                scope: "workspace",
                optionID: "decline",
                approved: false
            )
        )

        XCTAssertEqual(response.permissions, [])
        XCTAssertNil(response.scope)
    }

    func testPermissionsGrantFallsBackToRequestedPermissions() throws {
        let request = RuntimePermissionsRequest(
            id: 2,
            method: "item/permissions/requestApproval",
            threadID: "thread-1",
            turnID: nil,
            itemID: nil,
            reason: "Need write access",
            cwd: "/tmp",
            permissions: ["project.write"],
            grantRoot: "workspace",
            detail: "Need project.write"
        )

        let response = try RemoteRuntimeRequestResponseInterpreter.permissionsResponse(
            for: request,
            payload: RemoteControlRuntimeRequestResponse(optionID: "grant", approved: true)
        )

        XCTAssertEqual(response.permissions, Set(["project.write"]))
        XCTAssertEqual(response.scope, "workspace")
    }

    func testDynamicToolCallDeclineCanBeDerivedFromOptionID() throws {
        let approved = try RemoteRuntimeRequestResponseInterpreter.dynamicToolCallApproval(
            payload: RemoteControlRuntimeRequestResponse(optionID: "decline")
        )

        XCTAssertFalse(approved)
    }
}
