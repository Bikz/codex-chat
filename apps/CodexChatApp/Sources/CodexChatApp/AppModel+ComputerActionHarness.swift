import CodexComputerActions
import CodexKit
import Foundation

extension AppModel {
    private enum ComputerActionHarnessConstants {
        static let protocolVersion = 1
        static let runTokenLifetimeSeconds: TimeInterval = 15 * 60
        static let maxArgumentsJSONStringLength = 64 * 1024
    }

    func startComputerActionHarnessIfNeeded() {
        guard computerActionHarnessServer == nil else {
            return
        }

        guard let environment = effectiveComputerActionHarnessEnvironment() else {
            appendLog(.debug, "Computer action harness disabled: missing socket/token environment.")
            return
        }

        let server = ComputerActionHarnessServer(
            socketPath: environment.socketPath,
            requestHandler: { [weak self] request in
                guard let self else {
                    return HarnessInvokeResponse(
                        requestID: request.requestID,
                        status: .unauthorized,
                        summary: "Harness is unavailable.",
                        errorCode: "app_unavailable",
                        errorMessage: "CodexChat app model is unavailable."
                    )
                }
                return await handleHarnessInvokeRequest(request)
            },
            logHandler: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.appendLog(.warning, message)
                }
            }
        )

        do {
            try server.start()
            computerActionHarnessServer = server
            appendLog(.info, "Computer action harness started at \(environment.socketPath)")
        } catch {
            appendLog(.error, "Failed to start computer action harness: \(error.localizedDescription)")
        }
    }

    func registerHarnessRunContext(
        threadID: UUID,
        projectID: UUID
    ) -> String {
        purgeExpiredHarnessRunContexts()
        let token = UUID().uuidString.lowercased()
        harnessRunContextByToken[token] = HarnessRunContext(
            threadID: threadID,
            projectID: projectID,
            expiresAt: Date().addingTimeInterval(ComputerActionHarnessConstants.runTokenLifetimeSeconds)
        )
        return token
    }

    func prepareHarnessSkillInputIfNeeded(
        text: String,
        threadID: UUID,
        projectID: UUID
    ) -> RuntimeSkillInput? {
        guard isHarnessRelevantIntentText(text) else {
            return nil
        }

        let runToken = registerHarnessRunContext(threadID: threadID, projectID: projectID)
        do {
            return try writeHarnessSkillFile(runToken: runToken)
        } catch {
            appendLog(.warning, "Failed to prepare harness skill input: \(error.localizedDescription)")
            return nil
        }
    }

    private func handleHarnessInvokeRequest(_ request: HarnessInvokeRequest) async -> HarnessInvokeResponse {
        if request.protocolVersion != ComputerActionHarnessConstants.protocolVersion {
            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .invalid,
                summary: "Unsupported harness protocol version.",
                errorCode: "unsupported_protocol",
                errorMessage: "Expected protocolVersion \(ComputerActionHarnessConstants.protocolVersion)."
            )
        }

        guard let environment = effectiveComputerActionHarnessEnvironment(),
              let sessionToken = request.sessionToken,
              sessionToken == environment.sessionToken
        else {
            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .unauthorized,
                summary: "Harness session token is invalid.",
                errorCode: "invalid_session_token",
                errorMessage: "Request sessionToken did not match the current harness session."
            )
        }

        purgeExpiredHarnessRunContexts()
        guard let context = harnessRunContextByToken[request.runToken] else {
            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .unauthorized,
                summary: "Run token is invalid or expired.",
                errorCode: "invalid_run_token",
                errorMessage: "Request runToken was not found or expired."
            )
        }

        guard request.argumentsJson.count <= ComputerActionHarnessConstants.maxArgumentsJSONStringLength else {
            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .invalid,
                summary: "Arguments payload is too large.",
                errorCode: "arguments_too_large",
                errorMessage: "argumentsJson exceeded max size."
            )
        }

        let arguments: [String: String]
        do {
            arguments = try decodeHarnessArguments(json: request.argumentsJson)
        } catch {
            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .invalid,
                summary: "Failed to parse action arguments.",
                errorCode: "invalid_arguments_json",
                errorMessage: error.localizedDescription
            )
        }

        do {
            try await runNativeComputerAction(
                actionID: request.actionID,
                arguments: arguments,
                threadID: context.threadID,
                projectID: context.projectID
            )

            if let preview = pendingComputerActionPreview,
               preview.threadID == context.threadID
            {
                return HarnessInvokeResponse(
                    requestID: request.requestID,
                    status: .queuedForApproval,
                    summary: preview.artifact.summary,
                    pendingApprovalID: preview.id
                )
            }

            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .executed,
                summary: computerActionStatusMessage ?? "Action executed."
            )
        } catch let actionError as ComputerActionError {
            let responseStatus: HarnessInvokeStatus
            let errorCode: String

            switch actionError {
            case .permissionDenied:
                if permissionRecoveryTargetForComputerAction(
                    actionID: request.actionID,
                    error: actionError,
                    arguments: arguments
                ) != nil {
                    responseStatus = .permissionBlocked
                    errorCode = "permission_blocked"
                } else {
                    responseStatus = .denied
                    errorCode = "permission_denied"
                }
            case .invalidArguments, .previewContextMismatch, .invalidPreviewArtifact, .previewRequired:
                responseStatus = .invalid
                errorCode = "invalid_arguments"
            case .unsupported:
                responseStatus = .invalid
                errorCode = "unsupported_action"
            case .executionFailed:
                responseStatus = .invalid
                errorCode = "execution_failed"
            }

            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: responseStatus,
                summary: actionError.localizedDescription,
                errorCode: errorCode,
                errorMessage: actionError.localizedDescription
            )
        } catch {
            return HarnessInvokeResponse(
                requestID: request.requestID,
                status: .invalid,
                summary: "Failed to execute action.",
                errorCode: "unknown_error",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func decodeHarnessArguments(json: String) throws -> [String: String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return [:]
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw ComputerActionError.invalidArguments("argumentsJson was not valid UTF-8 text.")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw ComputerActionError.invalidArguments("argumentsJson must be a JSON object.")
        }

        var parsed: [String: String] = [:]
        parsed.reserveCapacity(dictionary.count)

        for (key, value) in dictionary {
            if let stringValue = value as? String {
                parsed[key] = stringValue
                continue
            }

            if value is NSNull {
                continue
            }

            if let number = value as? NSNumber {
                parsed[key] = number.stringValue
                continue
            }

            if JSONSerialization.isValidJSONObject(value),
               let nestedData = try? JSONSerialization.data(withJSONObject: value),
               let nestedText = String(data: nestedData, encoding: .utf8)
            {
                parsed[key] = nestedText
                continue
            }

            parsed[key] = String(describing: value)
        }

        return parsed
    }

    func effectiveComputerActionHarnessEnvironment() -> ComputerActionHarnessEnvironment? {
        if let configured = computerActionHarnessEnvironment {
            return configured
        }

        let processEnvironment = ProcessInfo.processInfo.environment
        guard let socketPath = processEnvironment["CODEXCHAT_HARNESS_SOCKET"],
              let sessionToken = processEnvironment["CODEXCHAT_HARNESS_SESSION_TOKEN"],
              !socketPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return ComputerActionHarnessEnvironment(
            socketPath: socketPath,
            sessionToken: sessionToken,
            wrapperPath: processEnvironment["CODEXCHAT_HARNESS_WRAPPER_PATH"] ?? "codexchat-action"
        )
    }

    private func purgeExpiredHarnessRunContexts() {
        let now = Date()
        harnessRunContextByToken = harnessRunContextByToken.filter { $0.value.expiresAt > now }
    }

    private func writeHarnessSkillFile(runToken: String) throws -> RuntimeSkillInput {
        let directoryURL = storagePaths.systemURL
            .appendingPathComponent("computer-action-harness/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let skillURL = directoryURL.appendingPathComponent("\(runToken).md", isDirectory: false)
        let content = harnessSkillContent(runToken: runToken)
        try content.write(to: skillURL, atomically: true, encoding: .utf8)

        return RuntimeSkillInput(
            name: "computer-action-harness",
            path: skillURL.path
        )
    }

    private func harnessSkillContent(runToken: String) -> String {
        let wrapperPath = effectiveComputerActionHarnessEnvironment()?.wrapperPath ?? "codexchat-action"
        let actionIDs = computerActionRegistry.allProviders.map(\.actionID).sorted().joined(separator: ", ")

        return """
        ---
        name: computer-action-harness
        description: Invoke CodexChat native computer actions through the local harness endpoint.
        ---

        Use the local harness wrapper when the user asks to perform a native computer action:

        `\(wrapperPath) invoke --run-token "\(runToken)" --action-id "<action-id>" --arguments-json '{"key":"value"}'`

        Constraints:
        - Use only the provided run token: `\(runToken)`.
        - Send only valid JSON objects for `--arguments-json`.
        - If response status is `queued_for_approval`, wait for user confirmation.
        - If response status is `permission_blocked`, provide remediation guidance.

        Available action IDs:
        - \(actionIDs)
        """
    }

    private func isHarnessRelevantIntentText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = [
            "imessage",
            "i message",
            "text ",
            "send message",
            "calendar",
            "event",
            "reminder",
            "apple script",
            "applescript",
            "jxa",
            "move file",
            "rename file",
            "finder",
            "desktop",
        ]
        return keywords.contains(where: { lowered.contains($0) })
    }
}
