import Foundation

public enum ModHookEventName: String, CaseIterable, Hashable, Sendable, Codable {
    case threadStarted = "thread.started"
    case turnStarted = "turn.started"
    case assistantDelta = "assistant.delta"
    case actionCard = "action.card"
    case approvalRequested = "approval.requested"
    case turnCompleted = "turn.completed"
    case turnFailed = "turn.failed"
    case transcriptPersisted = "transcript.persisted"
}

public struct ModExtensionHandler: Hashable, Sendable, Codable {
    public var command: [String]
    public var cwd: String?

    public init(command: [String], cwd: String? = nil) {
        self.command = command
        self.cwd = cwd
    }
}

public struct ModExtensionPermissions: Hashable, Sendable, Codable {
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
}

public struct ModHookDefinition: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var event: ModHookEventName
    public var handler: ModExtensionHandler
    public var permissions: ModExtensionPermissions
    public var timeoutMs: Int
    public var debounceMs: Int

    public init(
        id: String,
        event: ModHookEventName,
        handler: ModExtensionHandler,
        permissions: ModExtensionPermissions = .init(),
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

public struct ModAutomationDefinition: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var schedule: String
    public var handler: ModExtensionHandler
    public var permissions: ModExtensionPermissions
    public var timeoutMs: Int

    public init(
        id: String,
        schedule: String,
        handler: ModExtensionHandler,
        permissions: ModExtensionPermissions = .init(),
        timeoutMs: Int = 60000
    ) {
        self.id = id
        self.schedule = schedule
        self.handler = handler
        self.permissions = permissions
        self.timeoutMs = timeoutMs
    }
}

public struct ModUISlots: Hashable, Sendable, Codable {
    public struct RightInspectorSource: Hashable, Sendable, Codable {
        public var type: String
        public var hookID: String?

        enum CodingKeys: String, CodingKey {
            case type
            case hookID = "hookId"
        }

        public init(type: String, hookID: String? = nil) {
            self.type = type
            self.hookID = hookID
        }
    }

    public struct RightInspector: Hashable, Sendable, Codable {
        public var enabled: Bool
        public var title: String?
        public var source: RightInspectorSource?

        public init(enabled: Bool, title: String? = nil, source: RightInspectorSource? = nil) {
            self.enabled = enabled
            self.title = title
            self.source = source
        }
    }

    public var rightInspector: RightInspector?

    public init(rightInspector: RightInspector? = nil) {
        self.rightInspector = rightInspector
    }
}
