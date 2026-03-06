@testable import CodexChatShared
import CodexMods
import Foundation
import XCTest

@MainActor
final class AppModelModsSurfaceDiscoveryTests: XCTestCase {
    func testRefreshModsSurfaceLoadsHealthyModsWhenAnotherModIsMalformed() async throws {
        let storageRoot = try makeTempDirectory(prefix: "mods-surface-discovery")
        let previousRoot = UserDefaults.standard.string(forKey: CodexChatStoragePaths.rootPreferenceKey)
        UserDefaults.standard.set(storageRoot.path, forKey: CodexChatStoragePaths.rootPreferenceKey)
        defer {
            if let previousRoot {
                UserDefaults.standard.set(previousRoot, forKey: CodexChatStoragePaths.rootPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CodexChatStoragePaths.rootPreferenceKey)
            }
            try? FileManager.default.removeItem(at: storageRoot)
        }

        let storagePaths = CodexChatStoragePaths(rootURL: storageRoot)
        try storagePaths.ensureRootStructure()

        let discoveryService = UIModDiscoveryService()
        _ = try discoveryService.writeSampleMod(to: storagePaths.globalModsURL.path, name: "good-mod")

        let badModDirectory = storagePaths.globalModsURL.appendingPathComponent("bad-mod", isDirectory: true)
        try FileManager.default.createDirectory(at: badModDirectory, withIntermediateDirectories: true)
        try Data(
            """
            {
              "schemaVersion": 2,
              "manifest": { "id": "acme.bad-mod", "name": "Bad Mod", "version": "1.0.0" },
              "theme": {}
            }
            """.utf8
        ).write(to: badModDirectory.appendingPathComponent("ui.mod.json", isDirectory: false), options: [.atomic])

        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )

        model.refreshModsSurface()

        try await eventually(timeoutSeconds: 5) {
            if case let .loaded(surface) = model.modsState {
                return surface.globalMods.map(\.definition.manifest.id) == ["good-mod"]
            }
            return false
        }

        if case let .loaded(surface) = model.modsState {
            XCTAssertEqual(surface.globalMods.map(\.definition.manifest.id), ["good-mod"])
            XCTAssertTrue(surface.projectMods.isEmpty)
        } else {
            XCTFail("Expected mods surface to load successfully")
        }

        XCTAssertEqual(
            model.modStatusMessage,
            "Some mods were skipped because they are invalid. Check logs for details."
        )
    }

    func testRefreshModsSurfaceClearsInvalidWarningAfterBadModIsRemoved() async throws {
        let storageRoot = try makeTempDirectory(prefix: "mods-surface-discovery-clear")
        let previousRoot = UserDefaults.standard.string(forKey: CodexChatStoragePaths.rootPreferenceKey)
        UserDefaults.standard.set(storageRoot.path, forKey: CodexChatStoragePaths.rootPreferenceKey)
        defer {
            if let previousRoot {
                UserDefaults.standard.set(previousRoot, forKey: CodexChatStoragePaths.rootPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CodexChatStoragePaths.rootPreferenceKey)
            }
            try? FileManager.default.removeItem(at: storageRoot)
        }

        let storagePaths = CodexChatStoragePaths(rootURL: storageRoot)
        try storagePaths.ensureRootStructure()

        let discoveryService = UIModDiscoveryService()
        _ = try discoveryService.writeSampleMod(to: storagePaths.globalModsURL.path, name: "good-mod")

        let badModDirectory = storagePaths.globalModsURL.appendingPathComponent("bad-mod", isDirectory: true)
        try FileManager.default.createDirectory(at: badModDirectory, withIntermediateDirectories: true)
        try Data(
            """
            {
              "schemaVersion": 2,
              "manifest": { "id": "acme.bad-mod", "name": "Bad Mod", "version": "1.0.0" },
              "theme": {}
            }
            """.utf8
        ).write(to: badModDirectory.appendingPathComponent("ui.mod.json", isDirectory: false), options: [.atomic])

        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )

        model.refreshModsSurface()

        try await eventually(timeoutSeconds: 5) {
            model.modStatusMessage == "Some mods were skipped because they are invalid. Check logs for details."
        }

        try FileManager.default.removeItem(at: badModDirectory)
        model.refreshModsSurface()

        try await eventually(timeoutSeconds: 5) {
            if case let .loaded(surface) = model.modsState {
                return surface.globalMods.map(\.definition.manifest.id) == ["good-mod"] && model.modStatusMessage == nil
            }
            return false
        }

        XCTAssertNil(model.modStatusMessage)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func eventually(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            await Task.yield()
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
