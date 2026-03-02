@testable import CodexSkills
import XCTest

final class SkillLinkManagerTests: XCTestCase {
    func testEnsureProjectSkillLinkCreatesSymlinkIntoProjectSkillsDirectory() throws {
        let fixture = try makeFixture()
        defer { try? fixture.cleanup() }

        let manager = SkillLinkManager(sharedStoreRootURL: fixture.sharedStoreRoot)
        let sharedSkill = fixture.sharedStoreRoot.appendingPathComponent("agent-browser", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSkill, withIntermediateDirectories: true)

        let linkURL = try manager.ensureProjectSkillLink(
            folderName: "agent-browser",
            sharedSkillDirectoryURL: sharedSkill,
            projectRootURL: fixture.projectRoot
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
        XCTAssertEqual(destination, sharedSkill.path)
    }

    func testEnsureProjectSkillLinkRejectsSharedSkillOutsideStore() throws {
        let fixture = try makeFixture()
        defer { try? fixture.cleanup() }

        let manager = SkillLinkManager(sharedStoreRootURL: fixture.sharedStoreRoot)
        let outsideSkill = fixture.root.appendingPathComponent("outside-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideSkill, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try manager.ensureProjectSkillLink(
                folderName: "outside-skill",
                sharedSkillDirectoryURL: outsideSkill,
                projectRootURL: fixture.projectRoot
            )
        ) { error in
            guard case SkillLinkManagerError.sharedSkillOutsideStore = error else {
                return XCTFail("Expected sharedSkillOutsideStore, got \(error)")
            }
        }
    }

    func testEnsureProjectSkillLinkRejectsSharedStoreRootAsSkillDirectory() throws {
        let fixture = try makeFixture()
        defer { try? fixture.cleanup() }

        let manager = SkillLinkManager(sharedStoreRootURL: fixture.sharedStoreRoot)
        XCTAssertThrowsError(
            try manager.ensureProjectSkillLink(
                folderName: "shared-store",
                sharedSkillDirectoryURL: fixture.sharedStoreRoot,
                projectRootURL: fixture.projectRoot
            )
        ) { error in
            guard case SkillLinkManagerError.sharedSkillOutsideStore = error else {
                return XCTFail("Expected sharedSkillOutsideStore, got \(error)")
            }
        }
    }

    func testReconcileProjectSkillLinkRepairsBrokenSymlink() throws {
        let fixture = try makeFixture()
        defer { try? fixture.cleanup() }

        let manager = SkillLinkManager(sharedStoreRootURL: fixture.sharedStoreRoot)
        let sharedSkill = fixture.sharedStoreRoot.appendingPathComponent("atlas", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSkill, withIntermediateDirectories: true)

        let managedLink = fixture.projectRoot
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent("atlas", isDirectory: true)
        try FileManager.default.createDirectory(at: managedLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: managedLink.path,
            withDestinationPath: fixture.sharedStoreRoot
                .appendingPathComponent("missing-atlas", isDirectory: true)
                .path
        )

        let repaired = try manager.reconcileProjectSkillLink(
            folderName: "atlas",
            sharedSkillDirectoryURL: sharedSkill,
            projectRootURL: fixture.projectRoot
        )

        XCTAssertTrue(repaired)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: managedLink.path)
        XCTAssertEqual(destination, sharedSkill.path)
    }

    func testStoreKeyBuilderUsesNormalizedOwnerRepoWithStableFingerprint() {
        let key = SkillStoreKeyBuilder.makeKey(
            source: "https://github.com/openai/agent-browser.git"
        )
        XCTAssertTrue(key.hasPrefix("openai-agent-browser-"))
        XCTAssertEqual(key, SkillStoreKeyBuilder.makeKey(source: "https://github.com/openai/agent-browser.git"))
    }

    private func makeFixture() throws -> (root: URL, sharedStoreRoot: URL, projectRoot: URL, cleanup: () throws -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-link-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sharedStoreRoot = root.appendingPathComponent("shared-store", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedStoreRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        return (
            root: root,
            sharedStoreRoot: sharedStoreRoot,
            projectRoot: projectRoot,
            cleanup: { try FileManager.default.removeItem(at: root) }
        )
    }
}
