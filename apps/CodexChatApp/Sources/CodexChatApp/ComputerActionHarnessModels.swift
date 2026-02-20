import Foundation

struct ComputerActionHarnessEnvironment: Hashable, Sendable {
    let socketPath: String
    let sessionToken: String
    let wrapperPath: String
}

struct HarnessRunContext: Hashable, Sendable {
    let threadID: UUID
    let projectID: UUID
    let expiresAt: Date
}

struct HarnessInvokeRequest: Codable, Hashable, Sendable {
    let protocolVersion: Int
    let requestID: String
    let sessionToken: String?
    let runToken: String
    let actionID: String
    let argumentsJson: String
}

enum HarnessInvokeStatus: String, Codable, Hashable, Sendable {
    case queuedForApproval = "queued_for_approval"
    case executed
    case denied
    case invalid
    case unauthorized
    case permissionBlocked = "permission_blocked"
}

struct HarnessInvokeResponse: Codable, Hashable, Sendable {
    let requestID: String
    let status: HarnessInvokeStatus
    let summary: String
    let pendingApprovalID: String?
    let errorCode: String?
    let errorMessage: String?

    init(
        requestID: String,
        status: HarnessInvokeStatus,
        summary: String,
        pendingApprovalID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.requestID = requestID
        self.status = status
        self.summary = summary
        self.pendingApprovalID = pendingApprovalID
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}
