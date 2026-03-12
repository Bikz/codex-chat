import CodexKit
import Foundation

struct RuntimeRequestSupportAction: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
}

struct RuntimeRequestSupportChoice: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let description: String?
}

struct RuntimeRequestSupportSummary: Codable, Hashable, Identifiable, Sendable {
    let requestID: String
    let kind: RuntimeServerRequestKind
    let threadID: String?
    let title: String
    let summary: String
    let responseOptions: [RuntimeRequestSupportAction]
    let permissions: [String]
    let options: [RuntimeRequestSupportChoice]
    let scopeHint: String?
    let toolName: String?
    let serverName: String?

    var id: String {
        requestID
    }
}

enum RuntimeRequestSupportEventPhase: String, Codable, Hashable, Sendable {
    case requested
    case responded
    case resolved
    case reset
    case failed
}

struct RuntimeRequestSupportEvent: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let phase: RuntimeRequestSupportEventPhase
    let requestID: String
    let kind: RuntimeServerRequestKind
    let threadID: String?
    let title: String
    let summary: String
}

extension AppModel {
    static let runtimeRequestSupportHistoryLimit = 100

    func pendingRuntimeRequestSupportSummaries() -> [RuntimeRequestSupportSummary] {
        var summariesByID: [Int: RuntimeRequestSupportSummary] = [:]

        for (threadID, requests) in approvalStateMachine.pendingByThreadID {
            for request in requests {
                summariesByID[request.id] = runtimeRequestSupportSummary(
                    for: request,
                    localThreadID: threadID
                )
            }
        }

        for request in unscopedApprovalRequests {
            summariesByID[request.id] = runtimeRequestSupportSummary(for: request)
        }

        if let activeApprovalRequest {
            let localThreadID = approvalStateMachine.threadID(for: activeApprovalRequest.id)
            summariesByID[activeApprovalRequest.id] = runtimeRequestSupportSummary(
                for: activeApprovalRequest,
                localThreadID: localThreadID
            )
        }

        for (threadID, requests) in serverRequestStateMachine.pendingByThreadID {
            for request in requests {
                summariesByID[request.id] = runtimeRequestSupportSummary(
                    for: request,
                    localThreadID: threadID
                )
            }
        }

        for request in unscopedServerRequests {
            summariesByID[request.id] = runtimeRequestSupportSummary(for: request)
        }

        if let activeServerRequest {
            let localThreadID = serverRequestStateMachine.threadID(for: activeServerRequest.id)
            summariesByID[activeServerRequest.id] = runtimeRequestSupportSummary(
                for: activeServerRequest,
                localThreadID: localThreadID
            )
        }

        return summariesByID.values.sorted { lhs, rhs in
            if lhs.threadID != rhs.threadID {
                return (lhs.threadID ?? "") < (rhs.threadID ?? "")
            }
            if lhs.title != rhs.title {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.requestID < rhs.requestID
        }
    }

    func runtimeRequestSupportBreakdown() -> [RuntimeServerRequestKind: Int] {
        pendingRuntimeRequestSupportSummaries().reduce(into: [:]) { counts, summary in
            counts[summary.kind, default: 0] += 1
        }
    }

    func recordRuntimeRequestSupportEvent(
        phase: RuntimeRequestSupportEventPhase,
        summary: RuntimeRequestSupportSummary,
        timestamp: Date = Date()
    ) {
        runtimeRequestSupportEvents.insert(
            RuntimeRequestSupportEvent(
                id: UUID(),
                timestamp: timestamp,
                phase: phase,
                requestID: summary.requestID,
                kind: summary.kind,
                threadID: summary.threadID,
                title: summary.title,
                summary: summary.summary
            ),
            at: 0
        )

        if runtimeRequestSupportEvents.count > Self.runtimeRequestSupportHistoryLimit {
            runtimeRequestSupportEvents.removeLast(
                runtimeRequestSupportEvents.count - Self.runtimeRequestSupportHistoryLimit
            )
        }
    }

    func runtimeRequestSupportSummary(
        for request: RuntimeApprovalRequest,
        localThreadID: UUID? = nil
    ) -> RuntimeRequestSupportSummary {
        RuntimeRequestSupportSummary(
            requestID: String(request.id),
            kind: .approval,
            threadID: localThreadID?.uuidString,
            title: "Approval request pending",
            summary: conciseApprovalSummary(for: request),
            responseOptions: request.availableDecisions.map(runtimeRequestSupportAction(for:)),
            permissions: [],
            options: [],
            scopeHint: request.grantRoot,
            toolName: nil,
            serverName: nil
        )
    }

    func runtimeRequestSupportSummary(
        for request: RuntimeServerRequest,
        localThreadID: UUID? = nil
    ) -> RuntimeRequestSupportSummary {
        switch request {
        case let .approval(approval):
            return runtimeRequestSupportSummary(for: approval, localThreadID: localThreadID)
        case let .permissions(permission):
            let requestedPermissions = permission.permissions.sorted()
            var fragments: [String] = []
            if let reason = conciseSupportDetail(permission.reason) {
                fragments.append(reason)
            }
            if !requestedPermissions.isEmpty {
                fragments.append("Permissions: \(requestedPermissions.joined(separator: ", "))")
            }
            if let detail = conciseSupportDetail(permission.detail) {
                fragments.append(detail)
            }

            return RuntimeRequestSupportSummary(
                requestID: String(permission.id),
                kind: .permissionsApproval,
                threadID: localThreadID?.uuidString,
                title: "Permission request pending",
                summary: fragments.first ?? permission.method,
                responseOptions: [
                    RuntimeRequestSupportAction(id: "grant", label: "Grant"),
                    RuntimeRequestSupportAction(id: "decline", label: "Decline"),
                ],
                permissions: requestedPermissions,
                options: [],
                scopeHint: permission.grantRoot,
                toolName: nil,
                serverName: nil
            )
        case let .userInput(userInput):
            return RuntimeRequestSupportSummary(
                requestID: String(userInput.id),
                kind: .userInput,
                threadID: localThreadID?.uuidString,
                title: conciseSupportDetail(userInput.title) ?? "Input request pending",
                summary: conciseSupportDetail(userInput.prompt) ?? userInput.method,
                responseOptions: [
                    RuntimeRequestSupportAction(id: "submit", label: "Submit"),
                    RuntimeRequestSupportAction(id: "dismiss", label: "Dismiss"),
                ],
                permissions: [],
                options: userInput.options.map {
                    RuntimeRequestSupportChoice(
                        id: $0.id,
                        label: $0.label,
                        description: $0.description
                    )
                },
                scopeHint: nil,
                toolName: nil,
                serverName: nil
            )
        case let .mcpElicitation(mcp):
            let title = if let serverName = conciseSupportDetail(mcp.serverName) {
                "MCP elicitation: \(serverName)"
            } else {
                "MCP elicitation pending"
            }
            return RuntimeRequestSupportSummary(
                requestID: String(mcp.id),
                kind: .mcpElicitation,
                threadID: localThreadID?.uuidString,
                title: title,
                summary: conciseSupportDetail(mcp.prompt) ?? mcp.method,
                responseOptions: [
                    RuntimeRequestSupportAction(id: "submit", label: "Submit"),
                    RuntimeRequestSupportAction(id: "dismiss", label: "Dismiss"),
                ],
                permissions: [],
                options: [],
                scopeHint: nil,
                toolName: nil,
                serverName: conciseSupportDetail(mcp.serverName)
            )
        case let .dynamicToolCall(tool):
            return RuntimeRequestSupportSummary(
                requestID: String(tool.id),
                kind: .dynamicToolCall,
                threadID: localThreadID?.uuidString,
                title: "Dynamic tool call requested",
                summary: conciseSupportDetail(tool.toolName) ?? tool.method,
                responseOptions: [
                    RuntimeRequestSupportAction(id: "approve", label: "Approve"),
                    RuntimeRequestSupportAction(id: "decline", label: "Decline"),
                ],
                permissions: [],
                options: [],
                scopeHint: nil,
                toolName: conciseSupportDetail(tool.toolName),
                serverName: nil
            )
        }
    }

    private func conciseApprovalSummary(for request: RuntimeApprovalRequest) -> String {
        if let reason = conciseSupportDetail(request.reason) {
            return reason
        }
        if !request.command.isEmpty {
            return request.command.joined(separator: " ")
        }
        if let detail = conciseSupportDetail(request.detail) {
            return detail
        }
        return request.method
    }

    private func conciseSupportDetail(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        return trimmed
            .replacingOccurrences(of: "\n", with: " | ")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func runtimeRequestSupportAction(
        for option: RuntimeApprovalOption
    ) -> RuntimeRequestSupportAction {
        switch option {
        case .approveOnce:
            RuntimeRequestSupportAction(id: "approve_once", label: "Approve once")
        case .approveForSession:
            RuntimeRequestSupportAction(id: "approve_for_session", label: "Approve for session")
        case .decline:
            RuntimeRequestSupportAction(id: "decline", label: "Decline")
        case .cancel:
            RuntimeRequestSupportAction(id: "cancel", label: "Cancel")
        }
    }
}
