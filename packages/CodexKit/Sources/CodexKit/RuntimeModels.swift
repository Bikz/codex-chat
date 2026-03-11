import Foundation

public enum RuntimeStatus: String, CaseIterable, Codable, Sendable {
    case idle
    case starting
    case connected
    case error
}

public struct RuntimeCapabilities: Hashable, Sendable, Codable {
    public var supportsTurnSteer: Bool
    public var supportsFollowUpSuggestions: Bool
    public var supportsServerRequestResolution: Bool
    public var supportsTurnInterrupt: Bool
    public var supportsThreadResume: Bool
    public var supportsThreadFork: Bool
    public var supportsThreadList: Bool
    public var supportsThreadRead: Bool
    public var supportsPermissionsApproval: Bool
    public var supportsUserInputRequests: Bool
    public var supportsMCPElicitationRequests: Bool
    public var supportsDynamicToolCallRequests: Bool
    public var supportsPlanUpdates: Bool
    public var supportsDiffUpdates: Bool
    public var supportsTokenUsageUpdates: Bool
    public var supportsModelReroutes: Bool

    public init(
        supportsTurnSteer: Bool,
        supportsFollowUpSuggestions: Bool,
        supportsServerRequestResolution: Bool = false,
        supportsTurnInterrupt: Bool = false,
        supportsThreadResume: Bool = false,
        supportsThreadFork: Bool = false,
        supportsThreadList: Bool = false,
        supportsThreadRead: Bool = false,
        supportsPermissionsApproval: Bool = false,
        supportsUserInputRequests: Bool = false,
        supportsMCPElicitationRequests: Bool = false,
        supportsDynamicToolCallRequests: Bool = false,
        supportsPlanUpdates: Bool = false,
        supportsDiffUpdates: Bool = false,
        supportsTokenUsageUpdates: Bool = false,
        supportsModelReroutes: Bool = false
    ) {
        self.supportsTurnSteer = supportsTurnSteer
        self.supportsFollowUpSuggestions = supportsFollowUpSuggestions
        self.supportsServerRequestResolution = supportsServerRequestResolution
        self.supportsTurnInterrupt = supportsTurnInterrupt
        self.supportsThreadResume = supportsThreadResume
        self.supportsThreadFork = supportsThreadFork
        self.supportsThreadList = supportsThreadList
        self.supportsThreadRead = supportsThreadRead
        self.supportsPermissionsApproval = supportsPermissionsApproval
        self.supportsUserInputRequests = supportsUserInputRequests
        self.supportsMCPElicitationRequests = supportsMCPElicitationRequests
        self.supportsDynamicToolCallRequests = supportsDynamicToolCallRequests
        self.supportsPlanUpdates = supportsPlanUpdates
        self.supportsDiffUpdates = supportsDiffUpdates
        self.supportsTokenUsageUpdates = supportsTokenUsageUpdates
        self.supportsModelReroutes = supportsModelReroutes
    }

    public static let none = RuntimeCapabilities(
        supportsTurnSteer: false,
        supportsFollowUpSuggestions: false,
        supportsServerRequestResolution: false,
        supportsTurnInterrupt: false,
        supportsThreadResume: false,
        supportsThreadFork: false,
        supportsThreadList: false,
        supportsThreadRead: false,
        supportsPermissionsApproval: false,
        supportsUserInputRequests: false,
        supportsMCPElicitationRequests: false,
        supportsDynamicToolCallRequests: false,
        supportsPlanUpdates: false,
        supportsDiffUpdates: false,
        supportsTokenUsageUpdates: false,
        supportsModelReroutes: false
    )
}

public struct RuntimeClientInfo: Hashable, Sendable, Codable {
    public let name: String
    public let title: String
    public let version: String

    public init(name: String, title: String, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct RuntimeClientCapabilities: Hashable, Sendable, Codable {
    public let experimentalAPI: Bool
    public let optOutNotificationMethods: [String]

    public init(
        experimentalAPI: Bool = false,
        optOutNotificationMethods: [String] = []
    ) {
        self.experimentalAPI = experimentalAPI
        self.optOutNotificationMethods = optOutNotificationMethods
    }
}

public struct RuntimeVersionInfo: Hashable, Sendable, Codable, Comparable {
    public let rawValue: String
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(
        rawValue: String,
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: String? = nil
    ) {
        self.rawValue = rawValue
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var minorLine: String {
        "\(major).\(minor)"
    }

    public static func < (lhs: RuntimeVersionInfo, rhs: RuntimeVersionInfo) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case let (left?, right?):
            return left.localizedStandardCompare(right) == .orderedAscending
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (nil, nil):
            return false
        }
    }
}

public enum RuntimeSupportLevel: String, Hashable, Sendable, Codable {
    case validated
    case grace
    case unsupported
    case unknown
}

public struct RuntimeCompatibilityState: Hashable, Sendable, Codable {
    public let detectedVersion: RuntimeVersionInfo?
    public let supportLevel: RuntimeSupportLevel
    public let supportedMinorLine: String
    public let graceMinorLine: String
    public let degradedReasons: [String]
    public let disabledFeatures: [String]

    public init(
        detectedVersion: RuntimeVersionInfo?,
        supportLevel: RuntimeSupportLevel,
        supportedMinorLine: String,
        graceMinorLine: String,
        degradedReasons: [String],
        disabledFeatures: [String]
    ) {
        self.detectedVersion = detectedVersion
        self.supportLevel = supportLevel
        self.supportedMinorLine = supportedMinorLine
        self.graceMinorLine = graceMinorLine
        self.degradedReasons = degradedReasons
        self.disabledFeatures = disabledFeatures
    }

    public var isDegraded: Bool {
        supportLevel != .validated || !disabledFeatures.isEmpty || !degradedReasons.isEmpty
    }
}

public struct RuntimeHandshake: Hashable, Sendable, Codable {
    public let clientInfo: RuntimeClientInfo
    public let sentCapabilities: RuntimeClientCapabilities
    public let negotiatedCapabilities: RuntimeCapabilities
    public let runtimeVersion: RuntimeVersionInfo?
    public let compatibility: RuntimeCompatibilityState

    public init(
        clientInfo: RuntimeClientInfo,
        sentCapabilities: RuntimeClientCapabilities,
        negotiatedCapabilities: RuntimeCapabilities,
        runtimeVersion: RuntimeVersionInfo?,
        compatibility: RuntimeCompatibilityState
    ) {
        self.clientInfo = clientInfo
        self.sentCapabilities = sentCapabilities
        self.negotiatedCapabilities = negotiatedCapabilities
        self.runtimeVersion = runtimeVersion
        self.compatibility = compatibility
    }
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

    var wireDecision: String {
        switch self {
        case .approveOnce:
            "accept"
        case .approveForSession:
            "acceptForSession"
        case .decline:
            "decline"
        case .cancel:
            "cancel"
        }
    }
}

public enum RuntimeApprovalOption: String, Hashable, Sendable, Codable, CaseIterable {
    case approveOnce = "accept"
    case approveForSession = "acceptForSession"
    case decline
    case cancel

    public var title: String {
        switch self {
        case .approveOnce:
            "Approve Once"
        case .approveForSession:
            "Approve for Session"
        case .decline:
            "Decline"
        case .cancel:
            "Cancel"
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
    public let availableDecisions: [RuntimeApprovalOption]
    public let grantRoot: String?
    public let networkContext: String?
    public let detail: String
    public let rawPayload: JSONValue?

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
        availableDecisions: [RuntimeApprovalOption] = [.approveOnce, .approveForSession, .decline],
        grantRoot: String? = nil,
        networkContext: String? = nil,
        detail: String,
        rawPayload: JSONValue? = nil
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
        self.availableDecisions = availableDecisions
        self.grantRoot = grantRoot
        self.networkContext = networkContext
        self.detail = detail
        self.rawPayload = rawPayload
    }
}

public enum RuntimeServerRequestKind: String, Hashable, Sendable, Codable {
    case approval
    case permissionsApproval
    case userInput
    case mcpElicitation
    case dynamicToolCall
}

public struct RuntimePermissionsRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let reason: String?
    public let cwd: String?
    public let permissions: [String]
    public let grantRoot: String?
    public let detail: String
    public let rawPayload: JSONValue?

    public init(
        id: Int,
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        reason: String?,
        cwd: String?,
        permissions: [String],
        grantRoot: String?,
        detail: String,
        rawPayload: JSONValue? = nil
    ) {
        self.id = id
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reason = reason
        self.cwd = cwd
        self.permissions = permissions
        self.grantRoot = grantRoot
        self.detail = detail
        self.rawPayload = rawPayload
    }
}

public struct RuntimeUserInputOption: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct RuntimeUserInputRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let title: String?
    public let prompt: String
    public let placeholder: String?
    public let value: String?
    public let options: [RuntimeUserInputOption]
    public let detail: String
    public let rawPayload: JSONValue?

    public init(
        id: Int,
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        title: String?,
        prompt: String,
        placeholder: String?,
        value: String?,
        options: [RuntimeUserInputOption],
        detail: String,
        rawPayload: JSONValue? = nil
    ) {
        self.id = id
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.title = title
        self.prompt = prompt
        self.placeholder = placeholder
        self.value = value
        self.options = options
        self.detail = detail
        self.rawPayload = rawPayload
    }
}

public struct RuntimeMCPElicitationRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let serverName: String?
    public let prompt: String
    public let detail: String
    public let rawPayload: JSONValue?

    public init(
        id: Int,
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        serverName: String?,
        prompt: String,
        detail: String,
        rawPayload: JSONValue? = nil
    ) {
        self.id = id
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.serverName = serverName
        self.prompt = prompt
        self.detail = detail
        self.rawPayload = rawPayload
    }
}

public struct RuntimeDynamicToolCallRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let toolName: String
    public let arguments: JSONValue?
    public let detail: String
    public let rawPayload: JSONValue?

    public init(
        id: Int,
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        toolName: String,
        arguments: JSONValue?,
        detail: String,
        rawPayload: JSONValue? = nil
    ) {
        self.id = id
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.toolName = toolName
        self.arguments = arguments
        self.detail = detail
        self.rawPayload = rawPayload
    }
}

public enum RuntimeServerRequest: Hashable, Sendable {
    case approval(RuntimeApprovalRequest)
    case permissions(RuntimePermissionsRequest)
    case userInput(RuntimeUserInputRequest)
    case mcpElicitation(RuntimeMCPElicitationRequest)
    case dynamicToolCall(RuntimeDynamicToolCallRequest)

    public var id: Int {
        switch self {
        case let .approval(request):
            request.id
        case let .permissions(request):
            request.id
        case let .userInput(request):
            request.id
        case let .mcpElicitation(request):
            request.id
        case let .dynamicToolCall(request):
            request.id
        }
    }

    public var method: String {
        switch self {
        case let .approval(request):
            request.method
        case let .permissions(request):
            request.method
        case let .userInput(request):
            request.method
        case let .mcpElicitation(request):
            request.method
        case let .dynamicToolCall(request):
            request.method
        }
    }

    public var kind: RuntimeServerRequestKind {
        switch self {
        case .approval:
            .approval
        case .permissions:
            .permissionsApproval
        case .userInput:
            .userInput
        case .mcpElicitation:
            .mcpElicitation
        case .dynamicToolCall:
            .dynamicToolCall
        }
    }
}

public enum RuntimeServerRequestResponse: Hashable, Sendable {
    case approval(RuntimeApprovalDecision)
    case permissions(permissions: [String], scope: String?)
    case userInput(text: String?, optionID: String?)
    case mcpElicitation(text: String?)
    case dynamicToolCall(approved: Bool)

    var rpcResult: JSONValue {
        switch self {
        case let .approval(decision):
            return .object(["decision": .string(decision.wireDecision)])
        case let .permissions(permissions, scope):
            var payload: [String: JSONValue] = [
                "permissions": .array(permissions.map(JSONValue.string)),
            ]
            if let scope, !scope.isEmpty {
                payload["scope"] = .string(scope)
            }
            return .object(payload)
        case let .userInput(text, optionID):
            var payload: [String: JSONValue] = [:]
            if let text {
                payload["text"] = .string(text)
            }
            if let optionID {
                payload["optionId"] = .string(optionID)
            }
            return .object(payload)
        case let .mcpElicitation(text):
            if let text {
                return .object(["text": .string(text)])
            }
            return .object([:])
        case let .dynamicToolCall(approved):
            return .object(["approved": .bool(approved)])
        }
    }
}

public struct RuntimeServerRequestResolution: Hashable, Sendable, Codable {
    public let requestID: Int?
    public let method: String?
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let detail: String

    public init(
        requestID: Int?,
        method: String?,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        detail: String
    ) {
        self.requestID = requestID
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.detail = detail
    }
}

public struct RuntimeThreadStatusUpdate: Hashable, Sendable, Codable {
    public let threadID: String?
    public let status: String

    public init(threadID: String?, status: String) {
        self.threadID = threadID
        self.status = status
    }
}

public struct RuntimeTokenUsageUpdate: Hashable, Sendable, Codable {
    public let threadID: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(threadID: String?, inputTokens: Int?, outputTokens: Int?, totalTokens: Int?) {
        self.threadID = threadID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct RuntimeTurnDiffUpdate: Hashable, Sendable, Codable {
    public let threadID: String?
    public let turnID: String?
    public let diff: String?
    public let rawPayload: JSONValue?

    public init(threadID: String?, turnID: String?, diff: String?, rawPayload: JSONValue?) {
        self.threadID = threadID
        self.turnID = turnID
        self.diff = diff
        self.rawPayload = rawPayload
    }
}

public struct RuntimeTurnPlanUpdate: Hashable, Sendable, Codable {
    public let threadID: String?
    public let turnID: String?
    public let summary: String?
    public let rawPayload: JSONValue?

    public init(threadID: String?, turnID: String?, summary: String?, rawPayload: JSONValue?) {
        self.threadID = threadID
        self.turnID = turnID
        self.summary = summary
        self.rawPayload = rawPayload
    }
}

public struct RuntimeModelReroute: Hashable, Sendable, Codable {
    public let threadID: String?
    public let turnID: String?
    public let fromModel: String?
    public let toModel: String?
    public let reason: String?

    public init(
        threadID: String?,
        turnID: String?,
        fromModel: String?,
        toModel: String?,
        reason: String?
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.fromModel = fromModel
        self.toModel = toModel
        self.reason = reason
    }
}

public struct RuntimeFileChangeOutputDelta: Hashable, Sendable, Codable {
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

public struct RuntimeErrorNotice: Hashable, Sendable, Codable {
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let code: String?
    public let message: String
    public let rawPayload: JSONValue?

    public init(
        threadID: String?,
        turnID: String?,
        itemID: String?,
        code: String?,
        message: String,
        rawPayload: JSONValue? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.code = code
        self.message = message
        self.rawPayload = rawPayload
    }
}

public struct RuntimeUnknownNotification: Hashable, Sendable, Codable {
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue?) {
        self.method = method
        self.params = params
    }
}

public enum CodexRuntimeEvent: Hashable, Sendable {
    case threadStarted(threadID: String)
    case turnStarted(threadID: String?, turnID: String)
    case assistantMessageDelta(RuntimeAssistantMessageDelta)
    case commandOutputDelta(RuntimeCommandOutputDelta)
    case fileChangeOutputDelta(RuntimeFileChangeOutputDelta)
    case followUpSuggestions(RuntimeFollowUpSuggestionBatch)
    case fileChangesUpdated(RuntimeFileChangeUpdate)
    case serverRequest(RuntimeServerRequest)
    case serverRequestResolved(RuntimeServerRequestResolution)
    case approvalRequested(RuntimeApprovalRequest)
    case threadStatusUpdated(RuntimeThreadStatusUpdate)
    case tokenUsageUpdated(RuntimeTokenUsageUpdate)
    case turnDiffUpdated(RuntimeTurnDiffUpdate)
    case turnPlanUpdated(RuntimeTurnPlanUpdate)
    case modelRerouted(RuntimeModelReroute)
    case runtimeError(RuntimeErrorNotice)
    case unknownNotification(RuntimeUnknownNotification)
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
