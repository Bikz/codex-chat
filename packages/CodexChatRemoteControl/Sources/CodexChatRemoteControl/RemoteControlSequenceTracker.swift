import Foundation

public enum RemoteControlSequenceIngestResult: Sendable, Equatable {
    case accepted
    case stale(expectedNext: UInt64)
    case gapDetected(expectedNext: UInt64, received: UInt64)
}

public struct RemoteControlSequenceTracker: Sendable, Equatable {
    public private(set) var lastSeenSequence: UInt64?

    public init(lastSeenSequence: UInt64? = nil) {
        self.lastSeenSequence = lastSeenSequence
    }

    @discardableResult
    public mutating func ingest(_ sequence: UInt64) -> RemoteControlSequenceIngestResult {
        guard let lastSeenSequence else {
            self.lastSeenSequence = sequence
            return .accepted
        }

        let expectedNext = lastSeenSequence &+ 1

        if sequence == expectedNext {
            self.lastSeenSequence = sequence
            return .accepted
        }

        if sequence <= lastSeenSequence {
            return .stale(expectedNext: expectedNext)
        }

        return .gapDetected(expectedNext: expectedNext, received: sequence)
    }

    public mutating func reset(lastSeenSequence: UInt64? = nil) {
        self.lastSeenSequence = lastSeenSequence
    }
}
