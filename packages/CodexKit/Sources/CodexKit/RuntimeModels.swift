import Foundation

public enum RuntimeStatus: String, CaseIterable, Codable, Sendable {
    case idle
    case starting
    case connected
    case error
}

public struct RuntimeCapabilities: Hashable, Sendable {
    public var supportsTurnSteer: Bool
    public var supportsFollowUpSuggestions: Bool

    public init(supportsTurnSteer: Bool, supportsFollowUpSuggestions: Bool) {
        self.supportsTurnSteer = supportsTurnSteer
        self.supportsFollowUpSuggestions = supportsFollowUpSuggestions
    }

    public static let none = RuntimeCapabilities(
        supportsTurnSteer: false,
        supportsFollowUpSuggestions: false
    )
}

public struct RuntimeReasoningEffortOption: Hashable, Sendable, Codable {
    public let reasoningEffort: String
    public let description: String?

    public init(reasoningEffort: String, description: String? = nil) {
        self.reasoningEffort = reasoningEffort
        self.description = description
    }
}

public struct RuntimeModelInfo: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let model: String
    public let displayName: String
    public let description: String?
    public let supportedReasoningEfforts: [RuntimeReasoningEffortOption]
    public let defaultReasoningEffort: String?
    public let supportedWebSearchModes: [RuntimeWebSearchMode]?
    public let defaultWebSearchMode: RuntimeWebSearchMode?
    public let isDefault: Bool
    public let upgrade: String?

    public init(
        id: String,
        model: String,
        displayName: String,
        description: String? = nil,
        supportedReasoningEfforts: [RuntimeReasoningEffortOption] = [],
        defaultReasoningEffort: String? = nil,
        supportedWebSearchModes: [RuntimeWebSearchMode]? = nil,
        defaultWebSearchMode: RuntimeWebSearchMode? = nil,
        isDefault: Bool = false,
        upgrade: String? = nil
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedWebSearchModes = supportedWebSearchModes
        self.defaultWebSearchMode = defaultWebSearchMode
        self.isDefault = isDefault
        self.upgrade = upgrade
    }
}

public struct RuntimeModelList: Hashable, Sendable, Codable {
    public let models: [RuntimeModelInfo]
    public let nextCursor: String?

    public init(models: [RuntimeModelInfo], nextCursor: String? = nil) {
        self.models = models
        self.nextCursor = nextCursor
    }
}

public enum LogLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct LogEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

public struct RuntimeAction: Hashable, Sendable {
    public struct WorkerTrace: Hashable, Sendable, Codable {
        public let workerID: String?
        public let role: String?
        public let prompt: String?
        public let output: String?
        public let status: String?
        public let unavailableReason: String?

        public init(
            workerID: String? = nil,
            role: String? = nil,
            prompt: String? = nil,
            output: String? = nil,
            status: String? = nil,
            unavailableReason: String? = nil
        ) {
            self.workerID = workerID
            self.role = role
            self.prompt = prompt
            self.output = output
            self.status = status
            self.unavailableReason = unavailableReason
        }

        public var isUnavailable: Bool {
            prompt == nil && output == nil
        }
    }

    public let method: String
    public let itemID: String?
    public let itemType: String?
    public let threadID: String?
    public let turnID: String?
    public let title: String
    public let detail: String
    public let workerTrace: WorkerTrace?

    public init(
        method: String,
        itemID: String?,
        itemType: String?,
        threadID: String?,
        turnID: String?,
        title: String,
        detail: String,
        workerTrace: WorkerTrace? = nil
    ) {
        self.method = method
        self.itemID = itemID
        self.itemType = itemType
        self.threadID = threadID
        self.turnID = turnID
        self.title = title
        self.detail = detail
        self.workerTrace = workerTrace
    }
}

public struct RuntimeTurnCompletion: Hashable, Sendable {
    public let threadID: String?
    public let turnID: String?
    public let status: String
    public let errorMessage: String?

    public init(threadID: String?, turnID: String?, status: String, errorMessage: String?) {
        self.threadID = threadID
        self.turnID = turnID
        self.status = status
        self.errorMessage = errorMessage
    }
}

public enum RuntimeAuthMode: String, Codable, Sendable {
    case apiKey = "apikey"
    case chatGPT = "chatgpt"
    case chatGPTAuthTokens = "chatgptAuthTokens"
    case unknown

    public init(rawMode: String?) {
        switch rawMode {
        case RuntimeAuthMode.apiKey.rawValue:
            self = .apiKey
        case RuntimeAuthMode.chatGPT.rawValue:
            self = .chatGPT
        case RuntimeAuthMode.chatGPTAuthTokens.rawValue:
            self = .chatGPTAuthTokens
        default:
            self = .unknown
        }
    }
}

public struct RuntimeAccountSummary: Hashable, Sendable, Codable {
    public let type: String
    public let name: String?
    public let email: String?
    public let planType: String?

    public init(type: String, name: String? = nil, email: String?, planType: String?) {
        self.type = type
        self.name = name
        self.email = email
        self.planType = planType
    }
}

public struct RuntimeAccountState: Hashable, Sendable, Codable {
    public let account: RuntimeAccountSummary?
    public let authMode: RuntimeAuthMode
    public let requiresOpenAIAuth: Bool

    public init(account: RuntimeAccountSummary?, authMode: RuntimeAuthMode, requiresOpenAIAuth: Bool) {
        self.account = account
        self.authMode = authMode
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }

    public static let signedOut = RuntimeAccountState(
        account: nil,
        authMode: .unknown,
        requiresOpenAIAuth: true
    )
}

public struct RuntimeChatGPTLoginStart: Hashable, Sendable {
    public let loginID: String?
    public let authURL: URL

    public init(loginID: String?, authURL: URL) {
        self.loginID = loginID
        self.authURL = authURL
    }
}

public struct RuntimeLoginCompleted: Hashable, Sendable {
    public let loginID: String?
    public let success: Bool
    public let error: String?

    public init(loginID: String?, success: Bool, error: String?) {
        self.loginID = loginID
        self.success = success
        self.error = error
    }
}

public enum RuntimeSandboxMode: String, Hashable, Sendable, Codable {
    case readOnly
    case workspaceWrite
    case dangerFullAccess
}

public enum RuntimeApprovalPolicy: String, Hashable, Sendable, Codable {
    case untrusted
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never
}

public enum RuntimeWebSearchMode: String, Hashable, Sendable, Codable, CaseIterable {
    case cached
    case live
    case disabled
}

public struct RuntimeSafetyConfiguration: Hashable, Sendable, Codable {
    public let sandboxMode: RuntimeSandboxMode
    public let approvalPolicy: RuntimeApprovalPolicy
    public let networkAccess: Bool
    public let webSearch: RuntimeWebSearchMode
    public let writableRoots: [String]

    public init(
        sandboxMode: RuntimeSandboxMode,
        approvalPolicy: RuntimeApprovalPolicy,
        networkAccess: Bool,
        webSearch: RuntimeWebSearchMode,
        writableRoots: [String]
    ) {
        self.sandboxMode = sandboxMode
        self.approvalPolicy = approvalPolicy
        self.networkAccess = networkAccess
        self.webSearch = webSearch
        self.writableRoots = writableRoots
    }
}

public struct RuntimeSkillInput: Hashable, Sendable, Codable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum RuntimeInputItem: Hashable, Sendable, Codable {
    case text(String)
    case image(url: String)
    case localImage(path: String)
    case skill(RuntimeSkillInput)
    case mention(name: String, path: String)
}

public struct RuntimeTurnOptions: Hashable, Sendable, Codable {
    public let model: String?
    public let effort: String?
    public let experimental: [String: Bool]

    public var reasoningEffort: String? {
        effort
    }

    public init(
        model: String? = nil,
        effort: String? = nil,
        reasoningEffort: String? = nil,
        experimental: [String: Bool] = [:]
    ) {
        self.model = model
        self.effort = effort ?? reasoningEffort
        self.experimental = experimental
    }
}

public enum RuntimeApprovalKind: String, Hashable, Sendable, Codable {
    case commandExecution
    case fileChange
    case unknown
}

public enum RuntimeApprovalDecision: Hashable, Sendable {
    case approveOnce
    case approveForSession
    case decline
    case cancel

    var rpcResult: JSONValue {
        switch self {
        case .approveOnce:
            .string("accept")
        case .approveForSession:
            .string("acceptForSession")
        case .decline:
            .string("decline")
        case .cancel:
            .string("cancel")
        }
    }
}

public struct RuntimeFileChange: Hashable, Sendable, Codable {
    public let path: String
    public let kind: String
    public let diff: String?

    public init(path: String, kind: String, diff: String?) {
        self.path = path
        self.kind = kind
        self.diff = diff
    }
}

public struct RuntimeFileChangeUpdate: Hashable, Sendable, Codable {
    public let itemID: String?
    public let threadID: String?
    public let turnID: String?
    public let status: String?
    public let changes: [RuntimeFileChange]

    public init(
        itemID: String?,
        threadID: String?,
        turnID: String?,
        status: String?,
        changes: [RuntimeFileChange]
    ) {
        self.itemID = itemID
        self.threadID = threadID
        self.turnID = turnID
        self.status = status
        self.changes = changes
    }
}

public struct RuntimeCommandOutputDelta: Hashable, Sendable, Codable {
    public let itemID: String
    public let threadID: String?
    public let turnID: String?
    public let delta: String

    public init(itemID: String, threadID: String?, turnID: String?, delta: String) {
        self.itemID = itemID
        self.threadID = threadID
        self.turnID = turnID
        self.delta = delta
    }
}

public enum RuntimeAssistantMessageChannel: String, Hashable, Sendable, Codable {
    case finalResponse = "final"
    case progress
    case system
    case unknown

    public init(rawChannel: String?) {
        let normalized = rawChannel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch normalized {
        case "", "final", "assistant", "response", "message":
            self = .finalResponse
        case "progress", "intermediary", "intermediate", "status", "update", "thinking":
            self = .progress
        case "system", "meta":
            self = .system
        default:
            self = .unknown
        }
    }
}

public struct RuntimeAssistantMessageDelta: Hashable, Sendable, Codable {
    public let itemID: String
    public let threadID: String?
    public let turnID: String?
    public let delta: String
    public let channel: RuntimeAssistantMessageChannel
    public let stage: String?

    public init(
        itemID: String,
        threadID: String?,
        turnID: String?,
        delta: String,
        channel: RuntimeAssistantMessageChannel = .finalResponse,
        stage: String? = nil
    ) {
        self.itemID = itemID
        self.threadID = threadID
        self.turnID = turnID
        self.delta = delta
        self.channel = channel
        self.stage = stage
    }
}

public struct RuntimeFollowUpSuggestion: Hashable, Sendable {
    public let id: String?
    public let text: String
    public let priority: Int?

    public init(id: String?, text: String, priority: Int?) {
        self.id = id
        self.text = text
        self.priority = priority
    }
}

public struct RuntimeFollowUpSuggestionBatch: Hashable, Sendable {
    public let threadID: String?
    public let turnID: String?
    public let suggestions: [RuntimeFollowUpSuggestion]

    public init(threadID: String?, turnID: String?, suggestions: [RuntimeFollowUpSuggestion]) {
        self.threadID = threadID
        self.turnID = turnID
        self.suggestions = suggestions
    }
}

public struct RuntimeApprovalRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let kind: RuntimeApprovalKind
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let reason: String?
    public let risk: String?
    public let cwd: String?
    public let command: [String]
    public let changes: [RuntimeFileChange]
    public let detail: String

    public init(
        id: Int,
        kind: RuntimeApprovalKind,
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        reason: String?,
        risk: String?,
        cwd: String?,
        command: [String],
        changes: [RuntimeFileChange],
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reason = reason
        self.risk = risk
        self.cwd = cwd
        self.command = command
        self.changes = changes
        self.detail = detail
    }
}

public enum CodexRuntimeEvent: Hashable, Sendable {
    case threadStarted(threadID: String)
    case turnStarted(threadID: String?, turnID: String)
    case assistantMessageDelta(RuntimeAssistantMessageDelta)
    case commandOutputDelta(RuntimeCommandOutputDelta)
    case followUpSuggestions(RuntimeFollowUpSuggestionBatch)
    case fileChangesUpdated(RuntimeFileChangeUpdate)
    case approvalRequested(RuntimeApprovalRequest)
    case action(RuntimeAction)
    case turnCompleted(RuntimeTurnCompletion)
    case accountUpdated(authMode: RuntimeAuthMode)
    case accountLoginCompleted(RuntimeLoginCompleted)
}

public enum CodexRuntimeError: LocalizedError, Sendable {
    case binaryNotFound
    case processNotRunning
    case handshakeFailed(String)
    case timedOut(String)
    case invalidResponse(String)
    case rpcError(code: Int, message: String)
    case transportClosed

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Codex CLI was not found on PATH."
        case .processNotRunning:
            "Codex runtime process is not running."
        case let .handshakeFailed(detail):
            "Codex runtime handshake failed: \(detail)"
        case let .timedOut(operation):
            "Codex runtime timed out while \(operation)."
        case let .invalidResponse(detail):
            "Codex runtime returned an invalid response: \(detail)"
        case let .rpcError(_, message):
            "Codex runtime RPC error: \(message)"
        case .transportClosed:
            "Codex runtime transport closed unexpectedly."
        }
    }
}
