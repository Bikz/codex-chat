@testable import CodexChatShared
import Foundation
import XCTest

@MainActor
final class ActiveTurnContextMappingTests: XCTestCase {
    func testUpsertActiveTurnContextRegistersRuntimeThreadMapping() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let context = makeContext(threadID: threadID, runtimeThreadID: "thr_one")

        model.upsertActiveTurnContext(context)

        XCTAssertEqual(model.runtimeThreadIDByLocalThreadID[threadID], "thr_one")
        XCTAssertEqual(model.localThreadIDByRuntimeThreadID["thr_one"], threadID)
    }

    func testUpdateActiveTurnContextRewritesRuntimeThreadMapping() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.upsertActiveTurnContext(makeContext(threadID: threadID, runtimeThreadID: "thr_old"))

        _ = model.updateActiveTurnContext(for: threadID) { context in
            context.runtimeThreadID = "thr_new"
        }

        XCTAssertNil(model.localThreadIDByRuntimeThreadID["thr_old"])
        XCTAssertEqual(model.runtimeThreadIDByLocalThreadID[threadID], "thr_new")
        XCTAssertEqual(model.localThreadIDByRuntimeThreadID["thr_new"], threadID)
    }

    private func makeContext(threadID: UUID, runtimeThreadID: String) -> AppModel.ActiveTurnContext {
        AppModel.ActiveTurnContext(
            localTurnID: UUID(),
            localThreadID: threadID,
            projectID: UUID(),
            projectPath: "/tmp",
            runtimeThreadID: runtimeThreadID,
            runtimeTurnID: nil,
            memoryWriteMode: .off,
            userText: "user",
            assistantText: "",
            actions: [],
            startedAt: Date()
        )
    }
}
