import CodexChatCore
import Foundation

public struct ComputerActionRequest: Hashable, Sendable {
    public let runContextID: String
    public let arguments: [String: String]
    public let artifactDirectoryPath: String?

    public init(
        runContextID: String,
        arguments: [String: String] = [:],
        artifactDirectoryPath: String? = nil
    ) {
        self.runContextID = runContextID
        self.arguments = arguments
        self.artifactDirectoryPath = artifactDirectoryPath
    }
}

public struct ComputerActionPreviewArtifact: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let actionID: String
    public let runContextID: String
    public let title: String
    public let summary: String
    public let detailsMarkdown: String
    public let data: [String: String]
    public let generatedAt: Date

    public init(
        actionID: String,
        runContextID: String,
        title: String,
        summary: String,
        detailsMarkdown: String,
        data: [String: String] = [:],
        generatedAt: Date = Date()
    ) {
        id = "\(actionID):\(runContextID)"
        self.actionID = actionID
        self.runContextID = runContextID
        self.title = title
        self.summary = summary
        self.detailsMarkdown = detailsMarkdown
        self.data = data
        self.generatedAt = generatedAt
    }
}

public struct ComputerActionExecutionResult: Hashable, Sendable, Codable {
    public let actionID: String
    public let runContextID: String
    public let summary: String
    public let detailsMarkdown: String
    public let metadata: [String: String]

    public init(
        actionID: String,
        runContextID: String,
        summary: String,
        detailsMarkdown: String,
        metadata: [String: String] = [:]
    ) {
        self.actionID = actionID
        self.runContextID = runContextID
        self.summary = summary
        self.detailsMarkdown = detailsMarkdown
        self.metadata = metadata
    }
}

public enum ComputerActionError: LocalizedError, Sendable {
    case invalidArguments(String)
    case previewRequired
    case previewContextMismatch
    case invalidPreviewArtifact
    case permissionDenied(String)
    case unsupported(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            message
        case .previewRequired:
            "Preview is required before execution."
        case .previewContextMismatch:
            "Preview artifact does not match the current run context."
        case .invalidPreviewArtifact:
            "Preview artifact is invalid for this action."
        case let .permissionDenied(message):
            message
        case let .unsupported(message):
            message
        case let .executionFailed(message):
            message
        }
    }
}

public protocol ComputerActionProvider: Sendable {
    var actionID: String { get }
    var displayName: String { get }
    var safetyLevel: ComputerActionSafetyLevel { get }
    var requiresConfirmation: Bool { get }

    func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact
    func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult
}

public extension ComputerActionProvider {
    func validate(preview: ComputerActionPreviewArtifact, request: ComputerActionRequest) throws {
        guard preview.actionID == actionID else {
            throw ComputerActionError.invalidPreviewArtifact
        }
        guard preview.runContextID == request.runContextID else {
            throw ComputerActionError.previewContextMismatch
        }
    }
}
