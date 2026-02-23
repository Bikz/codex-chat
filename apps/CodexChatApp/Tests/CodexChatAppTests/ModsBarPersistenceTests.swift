import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import Foundation
import XCTest

@MainActor
final class ModsBarPersistenceTests: XCTestCase {
    func testPersistedModsBarStateRestoresAcrossModelInstances() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-persist-roundtrip")
        let initialModel = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        initialModel.extensionModsBarIsVisible = false
        initialModel.extensionModsBarPresentationMode = .rail
        initialModel.extensionModsBarLastOpenPresentationMode = .expanded
        try await initialModel.persistModsBarVisibilityPreference()

        let restoredModel = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        await restoredModel.restoreModsBarVisibility()

        XCTAssertFalse(restoredModel.extensionModsBarIsVisible)
        XCTAssertEqual(restoredModel.extensionModsBarPresentationMode, .rail)
        XCTAssertEqual(restoredModel.extensionModsBarLastOpenPresentationMode, .expanded)
    }

    func testRestoreModsBarVisibilityFromLegacyMapDefaultsToPeekMode() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-legacy-map")
        try await repositories.preferenceRepository.setPreference(
            key: .extensionsLegacyModsBarVisibility,
            value: """
            {"thread-a":false,"thread-b":true}
            """
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        await model.restoreModsBarVisibility()

        XCTAssertTrue(model.extensionModsBarIsVisible)
        XCTAssertEqual(model.extensionModsBarPresentationMode, .peek)
        XCTAssertEqual(model.extensionModsBarLastOpenPresentationMode, .peek)
    }

    func testRestoreModsBarVisibilityFromLegacyBooleanDefaultsToPeekMode() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-legacy-bool")
        try await repositories.preferenceRepository.setPreference(
            key: .extensionsLegacyModsBarVisibility,
            value: "true"
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        await model.restoreModsBarVisibility()

        XCTAssertTrue(model.extensionModsBarIsVisible)
        XCTAssertEqual(model.extensionModsBarPresentationMode, .peek)
        XCTAssertEqual(model.extensionModsBarLastOpenPresentationMode, .peek)
    }

    func testReopenFromHiddenWithRailPreferenceRestoresPeekMode() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-rail-reopen-peek")
        let initialModel = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        initialModel.extensionModsBarIsVisible = false
        initialModel.extensionModsBarPresentationMode = .rail
        initialModel.extensionModsBarLastOpenPresentationMode = .rail
        try await initialModel.persistModsBarVisibilityPreference()

        let restoredModel = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        restoredModel.selectedThreadID = UUID()
        await restoredModel.restoreModsBarVisibility()
        restoredModel.toggleModsBar()

        XCTAssertTrue(restoredModel.extensionModsBarIsVisible)
        XCTAssertEqual(restoredModel.selectedModsBarPresentationMode, .peek)
    }

    func testModsBarStateRemainsVisibleAcrossThreadSelectionChanges() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let firstThreadID = UUID()
        let secondThreadID = UUID()
        model.selectedThreadID = firstThreadID
        model.setModsBarPresentationMode(.expanded)

        XCTAssertTrue(model.isModsBarVisibleForSelectedThread)
        XCTAssertEqual(model.selectedModsBarPresentationMode, .expanded)

        model.selectedThreadID = secondThreadID

        XCTAssertTrue(model.isModsBarVisibleForSelectedThread)
        XCTAssertEqual(model.selectedModsBarPresentationMode, .expanded)
    }

    private func makeRepositories(prefix: String) throws -> MetadataRepositories {
        let root = try makeTempDirectory(prefix: prefix)
        let database = try MetadataDatabase(databaseURL: root.appendingPathComponent("metadata.sqlite", isDirectory: false))
        return MetadataRepositories(database: database)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
