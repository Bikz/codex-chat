import CodexKit
import Foundation

actor RuntimeEventDispatchBridge {
    private enum Constants {
        static let flushIntervalNanoseconds: UInt64 = 20_000_000
        static let maxBatchSize = 64
    }

    private let handler: @MainActor ([CodexRuntimeEvent]) async -> Void

    private var pendingEvents: [CodexRuntimeEvent] = []
    private var flushTask: Task<Void, Never>?

    init(handler: @escaping @MainActor ([CodexRuntimeEvent]) async -> Void) {
        self.handler = handler
    }

    func enqueue(_ event: CodexRuntimeEvent) async {
        pendingEvents.append(event)

        if shouldFlushImmediately(event) || pendingEvents.count >= Constants.maxBatchSize {
            await flushNow()
            return
        }

        scheduleFlushIfNeeded()
    }

    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil

        guard !pendingEvents.isEmpty else {
            return
        }

        let batch = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        await handler(batch)
    }

    func stop() async {
        await flushNow()
        flushTask?.cancel()
        flushTask = nil
        pendingEvents.removeAll(keepingCapacity: false)
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else {
            return
        }

        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.flushIntervalNanoseconds)
            guard let self, !Task.isCancelled else {
                return
            }

            await flushNow()
        }
    }

    private func shouldFlushImmediately(_ event: CodexRuntimeEvent) -> Bool {
        switch event {
        case .turnCompleted:
            true
        case .approvalRequested:
            true
        case let .action(action):
            action.method == "runtime/terminated"
                || action.method == "turn/start/error"
                || action.method == "turn/error"
        case .assistantMessageDelta:
            false
        case .commandOutputDelta:
            false
        case .followUpSuggestions:
            false
        case .fileChangesUpdated:
            false
        case .threadStarted:
            false
        case .turnStarted:
            false
        case .accountUpdated:
            false
        case .accountLoginCompleted:
            false
        }
    }
}
