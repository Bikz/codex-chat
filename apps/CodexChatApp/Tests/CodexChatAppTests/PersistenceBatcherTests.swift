@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

final class PersistenceBatcherTests: XCTestCase {
    func testBatchedJobsFlushOnTimerWindow() async throws {
        let recorder = PersistenceBatchRecorder()
        let batcher = PersistenceBatcher { jobs in
            await recorder.record(jobs)
        }

        await batcher.enqueue(
            context: sampleContext(threadID: UUID()),
            completion: sampleCompletion(status: "completed"),
            durability: .batched
        )
        await batcher.enqueue(
            context: sampleContext(threadID: UUID()),
            completion: sampleCompletion(status: "completed"),
            durability: .batched
        )

        try await eventually(timeoutSeconds: 1.2) {
            await recorder.totalJobs() == 2
        }

        let batchCount = await recorder.batchCount()
        XCTAssertEqual(batchCount, 1)
    }

    func testImmediateDurabilityFlushesPendingJobs() async throws {
        let recorder = PersistenceBatchRecorder()
        let batcher = PersistenceBatcher { jobs in
            await recorder.record(jobs)
        }

        await batcher.enqueue(
            context: sampleContext(threadID: UUID()),
            completion: sampleCompletion(status: "completed"),
            durability: .batched
        )
        await batcher.enqueue(
            context: sampleContext(threadID: UUID()),
            completion: sampleCompletion(status: "failed", error: "boom"),
            durability: .immediate
        )

        try await eventually(timeoutSeconds: 0.5) {
            await recorder.totalJobs() == 2
        }
    }

    func testBatchedJobsFlushAtThresholdWithoutWaitingForTimer() async throws {
        let recorder = PersistenceBatchRecorder()
        let batcher = PersistenceBatcher { jobs in
            await recorder.record(jobs)
        }

        for _ in 0 ..< 8 {
            await batcher.enqueue(
                context: sampleContext(threadID: UUID()),
                completion: sampleCompletion(status: "completed"),
                durability: .batched
            )
        }

        try await eventually(timeoutSeconds: 0.5) {
            await recorder.totalJobs() == 8
        }
        let batchCount = await recorder.batchCount()
        XCTAssertEqual(batchCount, 1)
    }

    func testShutdownFlushesPendingJobsImmediately() async throws {
        let recorder = PersistenceBatchRecorder()
        let batcher = PersistenceBatcher { jobs in
            await recorder.record(jobs)
        }

        await batcher.enqueue(
            context: sampleContext(threadID: UUID()),
            completion: sampleCompletion(status: "completed"),
            durability: .batched
        )
        await batcher.enqueue(
            context: sampleContext(threadID: UUID()),
            completion: sampleCompletion(status: "completed"),
            durability: .batched
        )

        await batcher.shutdown()

        try await eventually(timeoutSeconds: 0.5) {
            await recorder.totalJobs() == 2
        }
        let batchCount = await recorder.batchCount()
        XCTAssertEqual(batchCount, 1)
    }

    private func sampleContext(threadID: UUID) -> AppModel.ActiveTurnContext {
        AppModel.ActiveTurnContext(
            localTurnID: UUID(),
            localThreadID: threadID,
            projectID: UUID(),
            projectPath: "/tmp",
            runtimeThreadID: "thr_test",
            runtimeTurnID: "turn_test",
            memoryWriteMode: .off,
            userText: "user",
            assistantText: "assistant",
            actions: [],
            startedAt: Date()
        )
    }

    private func sampleCompletion(status: String, error: String? = nil) -> RuntimeTurnCompletion {
        RuntimeTurnCompletion(
            threadID: "thr_test",
            turnID: "turn_test",
            status: status,
            errorMessage: error
        )
    }

    private func eventually(timeoutSeconds: TimeInterval, condition: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}

private actor PersistenceBatchRecorder {
    private var batchSizes: [Int] = []

    func record(_ jobs: [PersistenceBatcher.Job]) {
        batchSizes.append(jobs.count)
    }

    func totalJobs() -> Int {
        batchSizes.reduce(0, +)
    }

    func batchCount() -> Int {
        batchSizes.count
    }
}
