import Foundation

enum ShellSplitAxis: String, CaseIterable, Hashable {
    case horizontal
    case vertical
}

enum ShellPaneProcessStatus: String, Hashable {
    case running
    case exited
}

struct ShellPaneState: Identifiable, Hashable {
    let id: UUID
    var cwd: String
    var title: String
    var processStatus: ShellPaneProcessStatus
    var lastExitCode: Int32?
    var launchGeneration: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        cwd: String,
        title: String = "Shell",
        processStatus: ShellPaneProcessStatus = .running,
        lastExitCode: Int32? = nil,
        launchGeneration: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.processStatus = processStatus
        self.lastExitCode = lastExitCode
        self.launchGeneration = launchGeneration
        self.createdAt = createdAt
    }
}

indirect enum ShellSplitNode: Hashable {
    case leaf(ShellPaneState)
    case split(
        id: UUID,
        axis: ShellSplitAxis,
        ratio: Double,
        first: ShellSplitNode,
        second: ShellSplitNode
    )
}

struct ShellSessionState: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rootNode: ShellSplitNode
    var activePaneID: UUID
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        rootNode: ShellSplitNode,
        activePaneID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootNode = rootNode
        self.activePaneID = activePaneID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectShellWorkspaceState: Hashable {
    let projectID: UUID
    var sessions: [ShellSessionState]
    var selectedSessionID: UUID?

    init(projectID: UUID, sessions: [ShellSessionState] = [], selectedSessionID: UUID? = nil) {
        self.projectID = projectID
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
    }
}

extension ShellSplitNode {
    func firstLeafID() -> UUID? {
        switch self {
        case let .leaf(pane):
            pane.id
        case let .split(_, _, _, first, _):
            first.firstLeafID()
        }
    }

    func leafCount() -> Int {
        switch self {
        case .leaf:
            1
        case let .split(_, _, _, first, second):
            first.leafCount() + second.leafCount()
        }
    }
}

extension ProjectShellWorkspaceState {
    func selectedSession() -> ShellSessionState? {
        guard let selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == selectedSessionID })
    }
}
