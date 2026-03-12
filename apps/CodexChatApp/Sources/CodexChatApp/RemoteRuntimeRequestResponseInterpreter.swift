import CodexChatRemoteControl
import CodexKit
import Foundation

enum RemoteRuntimeRequestResponseInterpreter {
    static func permissionsResponse(
        for request: RuntimePermissionsRequest,
        payload: RemoteControlRuntimeRequestResponse?
    ) throws -> (permissions: Set<String>, scope: String?) {
        let requestedPermissions = Set(request.permissions)
        let explicitPermissions = Set(payload?.permissions ?? [])
        let normalizedScope = normalizedText(payload?.scope)
        let optionID = normalizedText(payload?.optionID)

        if payload?.approved == false || optionLooksNegative(optionID) {
            return ([], nil)
        }

        if payload?.approved == true || optionLooksAffirmative(optionID) || !explicitPermissions.isEmpty {
            let grantedPermissions = explicitPermissions.isEmpty ? requestedPermissions : explicitPermissions
            guard !grantedPermissions.isEmpty else {
                throw RemoteRuntimeRequestCommandError.invalidPayload
            }
            return (grantedPermissions, normalizedScope ?? request.grantRoot)
        }

        throw RemoteRuntimeRequestCommandError.invalidPayload
    }

    static func userInputResponse(
        for request: RuntimeUserInputRequest,
        payload: RemoteControlRuntimeRequestResponse?
    ) -> (text: String?, optionID: String?) {
        let text = normalizedText(payload?.text)
        let optionID = selectedOptionID(for: request.options, candidate: payload?.optionID)
        return (text, optionID)
    }

    static func mcpElicitationText(
        payload: RemoteControlRuntimeRequestResponse?
    ) -> String? {
        normalizedText(payload?.text)
    }

    static func dynamicToolCallApproval(
        payload: RemoteControlRuntimeRequestResponse?
    ) throws -> Bool {
        if let approved = payload?.approved {
            return approved
        }

        let optionID = normalizedText(payload?.optionID)
        if optionLooksAffirmative(optionID) {
            return true
        }
        if optionLooksNegative(optionID) {
            return false
        }

        throw RemoteRuntimeRequestCommandError.invalidPayload
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func selectedOptionID(
        for options: [RuntimeUserInputOption],
        candidate: String?
    ) -> String? {
        guard let normalizedCandidate = normalizedText(candidate) else {
            return nil
        }
        return options.contains(where: { $0.id == normalizedCandidate }) ? normalizedCandidate : nil
    }

    private static func optionLooksAffirmative(_ optionID: String?) -> Bool {
        guard let optionID else {
            return false
        }
        return optionID.range(
            of: "^(accept|allow|approve|yes|confirm|continue|grant|proceed|submit|ok)$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func optionLooksNegative(_ optionID: String?) -> Bool {
        guard let optionID else {
            return false
        }
        return optionID.range(
            of: "^(decline|deny|reject|cancel|no|stop|dismiss)$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
