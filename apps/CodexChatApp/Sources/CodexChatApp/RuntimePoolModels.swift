import Foundation

struct RuntimePoolWorkerID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    let rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    static func < (lhs: RuntimePoolWorkerID, rhs: RuntimePoolWorkerID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        "w\(rawValue)"
    }
}

enum RuntimePoolWorkerHealthState: String, Sendable, Codable {
    case idle
    case starting
    case healthy
    case degraded
    case restarting
    case stopped
}

struct RuntimePoolWorkerMetrics: Hashable, Sendable, Codable {
    let workerID: RuntimePoolWorkerID
    var health: RuntimePoolWorkerHealthState
    var queueDepth: Int
    var inFlightTurns: Int
    var failureCount: Int
    var restartCount: Int
    var lastStartAt: Date?
    var lastFailureAt: Date?

    init(
        workerID: RuntimePoolWorkerID,
        health: RuntimePoolWorkerHealthState = .idle,
        queueDepth: Int = 0,
        inFlightTurns: Int = 0,
        failureCount: Int = 0,
        restartCount: Int = 0,
        lastStartAt: Date? = nil,
        lastFailureAt: Date? = nil
    ) {
        self.workerID = workerID
        self.health = health
        self.queueDepth = queueDepth
        self.inFlightTurns = inFlightTurns
        self.failureCount = failureCount
        self.restartCount = restartCount
        self.lastStartAt = lastStartAt
        self.lastFailureAt = lastFailureAt
    }
}

struct RuntimePoolSnapshot: Hashable, Sendable, Codable {
    var configuredWorkerCount: Int
    var activeWorkerCount: Int
    var pinnedThreadCount: Int
    var totalQueuedTurns: Int
    var totalInFlightTurns: Int
    var workers: [RuntimePoolWorkerMetrics]

    static let empty = RuntimePoolSnapshot(
        configuredWorkerCount: 0,
        activeWorkerCount: 0,
        pinnedThreadCount: 0,
        totalQueuedTurns: 0,
        totalInFlightTurns: 0,
        workers: []
    )
}
