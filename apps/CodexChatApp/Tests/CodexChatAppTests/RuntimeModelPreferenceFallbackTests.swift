import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import XCTest

@MainActor
final class RuntimeModelPreferenceFallbackTests: XCTestCase {
    func testLoadCodexConfigRestoresPreferredModelWhenConfigModelIsUnset() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-model-pref-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        try await repositories.preferenceRepository.setPreference(key: .runtimeConfigMigrationV1, value: "1")
        try await repositories.preferenceRepository.setPreference(key: .runtimeDefaultModel, value: "gpt-5.3-codex")

        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )

        try await model.loadCodexConfig()

        XCTAssertEqual(model.defaultModel, "gpt-5.3-codex")
        XCTAssertEqual(model.configuredModelOverride(), "gpt-5.3-codex")
        XCTAssertEqual(model.runtimeTurnOptions().model, "gpt-5.3-codex")
    }

    func testSetDefaultModelClearsPreferredModelWhenReturningToRuntimeDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-model-pref-clear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        try await repositories.preferenceRepository.setPreference(key: .runtimeConfigMigrationV1, value: "1")
        try await repositories.preferenceRepository.setPreference(key: .runtimeDefaultModel, value: "gpt-5.3-codex")

        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )
        try await model.loadCodexConfig()
        XCTAssertEqual(model.defaultModel, "gpt-5.3-codex")

        model.setDefaultModel("")
        try await waitForPreference(
            key: .runtimeDefaultModel,
            expectedValue: "",
            in: repositories.preferenceRepository
        )

        XCTAssertNil(model.configuredModelOverride())
        XCTAssertNil(model.runtimeTurnOptions().model)
    }

    private func waitForPreference(
        key: AppPreferenceKey,
        expectedValue: String,
        in repository: any PreferenceRepository,
        timeout: TimeInterval = 3.0
    ) async throws {
        let start = Date()
        while true {
            let currentValue = try await repository.getPreference(key: key)
            if currentValue == expectedValue {
                return
            }

            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for preference \(key.rawValue) to become \(expectedValue)")
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
