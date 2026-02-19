import CodexChatCore
import Foundation

public protocol MessagesSender: Sendable {
    func send(message: String, to recipient: String) async throws
}

public protocol OsaScriptRunning: Sendable {
    func run(script: String, arguments: [String]) async throws -> String
}

public struct ProcessOsaScriptRunner: OsaScriptRunning {
    public init() {}

    public func run(script: String, arguments: [String]) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript", isDirectory: false)
        process.arguments = ["-l", "AppleScript", "-e", script] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ComputerActionError.executionFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class AppleScriptMessagesSender: MessagesSender {
    private let runner: any OsaScriptRunning

    public init(runner: any OsaScriptRunning = ProcessOsaScriptRunner()) {
        self.runner = runner
    }

    public func send(message: String, to recipient: String) async throws {
        let script = """
        on run argv
            set targetHandle to item 1 of argv
            set messageText to item 2 of argv
            tell application "Messages"
                set targetService to first service whose service type = iMessage
                set targetBuddy to buddy targetHandle of targetService
                send messageText to targetBuddy
            end tell
            return "ok"
        end run
        """

        _ = try await runner.run(script: script, arguments: [recipient, message])
    }
}

public final class MessagesSendAction: ComputerActionProvider {
    private let sender: any MessagesSender

    public init(sender: any MessagesSender = AppleScriptMessagesSender()) {
        self.sender = sender
    }

    public let actionID = "messages.send"
    public let displayName = "Messages Send"
    public let safetyLevel: ComputerActionSafetyLevel = .externallyVisible
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let recipient = request.arguments["recipient"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = (request.arguments["body"] ?? request.arguments["message"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !recipient.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide a recipient before sending a message.")
        }
        guard !message.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide a message body before sending.")
        }

        let details = """
        Recipient: `\(recipient)`

        Message preview:

        > \(message)
        """

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Message Draft Preview",
            summary: "Ready to send a message to \(recipient).",
            detailsMarkdown: details,
            data: [
                "recipient": recipient,
                "message": message,
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)

        guard let recipient = preview.data["recipient"], !recipient.isEmpty,
              let message = preview.data["message"], !message.isEmpty
        else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let requestedRecipient = request.arguments["recipient"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedMessage = (request.arguments["body"] ?? request.arguments["message"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let requestedRecipient,
           !requestedRecipient.isEmpty,
           requestedRecipient != recipient
        {
            throw ComputerActionError.invalidArguments("Recipient changed after preview. Generate a fresh preview before sending.")
        }

        if !requestedMessage.isEmpty,
           requestedMessage != message
        {
            throw ComputerActionError.invalidArguments("Message body changed after preview. Generate a fresh preview before sending.")
        }

        do {
            try await sender.send(message: message, to: recipient)
        } catch let error as ComputerActionError {
            throw error
        } catch {
            throw ComputerActionError.permissionDenied(
                "Messages send failed. Check Messages permissions in System Settings > Privacy & Security > Automation."
            )
        }

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: "Message sent to \(recipient).",
            detailsMarkdown: "Sent message to `\(recipient)`.",
            metadata: [
                "recipient": recipient,
                "sent": "true",
            ]
        )
    }
}
