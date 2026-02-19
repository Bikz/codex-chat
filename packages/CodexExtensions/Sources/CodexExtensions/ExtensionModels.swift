import Foundation

public enum ExtensionPermissionFlag: String, CaseIterable, Hashable, Sendable, Codable {
    case projectRead
    case projectWrite
    case network
    case runtimeControl
    case runWhenAppClosed
}

public struct ExtensionPermissionSet: Hashable, Sendable, Codable {
    public var projectRead: Bool
    public var projectWrite: Bool
    public var network: Bool
    public var runtimeControl: Bool
    public var runWhenAppClosed: Bool

    public init(
        projectRead: Bool = false,
        projectWrite: Bool = false,
        network: Bool = false,
        runtimeControl: Bool = false,
        runWhenAppClosed: Bool = false
    ) {
        self.projectRead = projectRead
        self.projectWrite = projectWrite
        self.network = network
        self.runtimeControl = runtimeControl
        self.runWhenAppClosed = runWhenAppClosed
    }

    public var requestedKeys: Set<ExtensionPermissionFlag> {
        var keys = Set<ExtensionPermissionFlag>()
        if projectRead { keys.insert(.projectRead) }
        if projectWrite { keys.insert(.projectWrite) }
        if network { keys.insert(.network) }
        if runtimeControl { keys.insert(.runtimeControl) }
        if runWhenAppClosed { keys.insert(.runWhenAppClosed) }
        return keys
    }
}

public struct ExtensionHandlerDefinition: Hashable, Sendable, Codable {
    public var command: [String]
    public var cwd: String?

    public init(command: [String], cwd: String? = nil) {
        self.command = command
        self.cwd = cwd
    }
}

public struct ExtensionHookDefinition: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var event: ExtensionEventName
    public var handler: ExtensionHandlerDefinition
    public var permissions: ExtensionPermissionSet
    public var timeoutMs: Int
    public var debounceMs: Int

    public init(
        id: String,
        event: ExtensionEventName,
        handler: ExtensionHandlerDefinition,
        permissions: ExtensionPermissionSet = .init(),
        timeoutMs: Int = 8000,
        debounceMs: Int = 0
    ) {
        self.id = id
        self.event = event
        self.handler = handler
        self.permissions = permissions
        self.timeoutMs = timeoutMs
        self.debounceMs = debounceMs
    }
}

public struct ExtensionAutomationDefinition: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var schedule: String
    public var handler: ExtensionHandlerDefinition
    public var permissions: ExtensionPermissionSet
    public var timeoutMs: Int

    public init(
        id: String,
        schedule: String,
        handler: ExtensionHandlerDefinition,
        permissions: ExtensionPermissionSet = .init(),
        timeoutMs: Int = 60000
    ) {
        self.id = id
        self.schedule = schedule
        self.handler = handler
        self.permissions = permissions
        self.timeoutMs = timeoutMs
    }
}

public struct ExtensionProjectContext: Hashable, Sendable, Codable {
    public var id: String
    public var path: String

    public init(id: String, path: String) {
        self.id = id
        self.path = path
    }
}

public struct ExtensionThreadContext: Hashable, Sendable, Codable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct ExtensionTurnContext: Hashable, Sendable, Codable {
    public var id: String
    public var status: String?

    public init(id: String, status: String? = nil) {
        self.id = id
        self.status = status
    }
}

public enum ExtensionEventName: String, Hashable, Sendable, Codable, CaseIterable {
    case threadStarted = "thread.started"
    case turnStarted = "turn.started"
    case assistantDelta = "assistant.delta"
    case actionCard = "action.card"
    case approvalRequested = "approval.requested"
    case modsBarAction = "modsBar.action"
    case turnCompleted = "turn.completed"
    case turnFailed = "turn.failed"
    case transcriptPersisted = "transcript.persisted"
}

public struct ExtensionEventEnvelope: Hashable, Sendable, Codable {
    public let event: ExtensionEventName
    public let timestamp: Date
    public let project: ExtensionProjectContext
    public let thread: ExtensionThreadContext
    public let turn: ExtensionTurnContext?
    public let payload: [String: String]

    public init(
        event: ExtensionEventName,
        timestamp: Date,
        project: ExtensionProjectContext,
        thread: ExtensionThreadContext,
        turn: ExtensionTurnContext? = nil,
        payload: [String: String] = [:]
    ) {
        self.event = event
        self.timestamp = timestamp
        self.project = project
        self.thread = thread
        self.turn = turn
        self.payload = payload
    }
}

public struct ExtensionWorkerInput: Hashable, Sendable, Codable {
    public var `protocol`: String
    public var event: String
    public var timestamp: String
    public var project: ExtensionProjectContext
    public var thread: ExtensionThreadContext
    public var turn: ExtensionTurnContext?
    public var payload: [String: String]

    public init(envelope: ExtensionEventEnvelope, iso8601Formatter: ISO8601DateFormatter = ExtensionWorkerInput.defaultFormatter()) {
        `protocol` = "codexchat.extension.v1"
        event = envelope.event.rawValue
        timestamp = iso8601Formatter.string(from: envelope.timestamp)
        project = envelope.project
        thread = envelope.thread
        turn = envelope.turn
        payload = envelope.payload
    }

    public static func defaultFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

public enum ExtensionArtifactOperation: String, Hashable, Sendable, Codable {
    case upsert
}

public struct ExtensionArtifactInstruction: Hashable, Sendable, Codable {
    public var path: String
    public var op: ExtensionArtifactOperation
    public var content: String

    public init(path: String, op: ExtensionArtifactOperation = .upsert, content: String) {
        self.path = path
        self.op = op
        self.content = content
    }
}

public struct ExtensionModsBarOutput: Hashable, Sendable, Codable {
    public enum Scope: String, Hashable, Sendable, Codable {
        case thread
        case global
    }

    public struct ActionPrompt: Hashable, Sendable, Codable {
        public var title: String
        public var message: String?
        public var placeholder: String?
        public var initialValue: String?
        public var submitLabel: String?

        public init(
            title: String,
            message: String? = nil,
            placeholder: String? = nil,
            initialValue: String? = nil,
            submitLabel: String? = nil
        ) {
            self.title = title
            self.message = message
            self.placeholder = placeholder
            self.initialValue = initialValue
            self.submitLabel = submitLabel
        }
    }

    public enum ActionKind: String, Hashable, Sendable, Codable {
        case emitEvent
        case promptThenEmitEvent
        case composerInsert = "composer.insert"
        case composerInsertAndSend = "composer.insertAndSend"
    }

    public struct Action: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        public var label: String
        public var kind: ActionKind
        public var payload: [String: String]
        public var prompt: ActionPrompt?

        public init(
            id: String,
            label: String,
            kind: ActionKind,
            payload: [String: String] = [:],
            prompt: ActionPrompt? = nil
        ) {
            self.id = id
            self.label = label
            self.kind = kind
            self.payload = payload
            self.prompt = prompt
        }
    }

    public var title: String?
    public var markdown: String
    public var scope: Scope?
    public var actions: [Action]?

    public init(
        title: String? = nil,
        markdown: String,
        scope: Scope? = nil,
        actions: [Action]? = nil
    ) {
        self.title = title
        self.markdown = markdown
        self.scope = scope
        self.actions = actions
    }
}

public struct ExtensionWorkerOutput: Hashable, Sendable, Codable {
    public var ok: Bool?
    public var modsBar: ExtensionModsBarOutput?
    public var artifacts: [ExtensionArtifactInstruction]?
    public var log: String?

    public init(
        ok: Bool? = nil,
        modsBar: ExtensionModsBarOutput? = nil,
        artifacts: [ExtensionArtifactInstruction]? = nil,
        log: String? = nil
    ) {
        self.ok = ok
        self.modsBar = modsBar
        self.artifacts = artifacts
        self.log = log
    }
}
