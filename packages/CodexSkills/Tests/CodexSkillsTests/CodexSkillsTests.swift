@testable import CodexSkills
import Darwin
import XCTest

final class CodexSkillsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexSkillsPackage.version, "0.1.0")
    }

    func testDiscoverSkillsScansProjectAndGlobalScopes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let agentsHome = root.appendingPathComponent(".agents", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)

        try createSkill(
            at: codexHome.appendingPathComponent("skills/global-skill", isDirectory: true),
            body: """
            ---
            name: global-skill
            description: Global skill description
            ---
            # Global Skill
            """
        )

        try createSkill(
            at: project.appendingPathComponent(".agents/skills/project-skill", isDirectory: true),
            body: """
            # Project Skill

            Project skill description.
            """,
            includeScripts: true
        )

        let service = SkillCatalogService(
            codexHomeURL: codexHome,
            agentsHomeURL: agentsHome
        )

        let discovered = try service.discoverSkills(projectPath: project.path)
        XCTAssertEqual(discovered.count, 2)

        let global = discovered.first(where: { $0.name == "global-skill" })
        XCTAssertEqual(global?.scope, .global)
        XCTAssertEqual(global?.description, "Global skill description")
        XCTAssertFalse(global?.hasScripts ?? true)

        let projectSkill = discovered.first(where: { $0.name == "Project Skill" })
        XCTAssertEqual(projectSkill?.scope, .project)
        XCTAssertEqual(projectSkill?.description, "Project skill description.")
        XCTAssertTrue(projectSkill?.hasScripts ?? false)
    }

    func testDiscoverSkillsDoesNotInvokeProcessRunnerOnRepeatedDiscovery() throws {
        final class InvocationCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }

            func read() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-discover-nogit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let agentsHome = root.appendingPathComponent(".agents", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let skillDirectory = codexHome.appendingPathComponent("skills/git-backed-skill", isDirectory: true)

        try createSkill(
            at: skillDirectory,
            body: """
            # Git Backed Skill

            Uses repo metadata.
            """
        )
        try FileManager.default.createDirectory(
            at: skillDirectory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let counter = InvocationCounter()
        let service = SkillCatalogService(
            codexHomeURL: codexHome,
            agentsHomeURL: agentsHome,
            processRunner: { _, _ in
                counter.increment()
                throw NSError(
                    domain: "CodexSkillsTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "discoverSkills should not invoke processRunner"]
                )
            }
        )

        let first = try service.discoverSkills(projectPath: project.path)
        let second = try service.discoverSkills(projectPath: project.path)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(counter.read(), 0)
        XCTAssertNil(first.first?.sourceURL)
    }

    func testDiscoverSkillsCacheInvalidatesWhenSkillDefinitionChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-cache-invalidate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let agentsHome = root.appendingPathComponent(".agents", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let skillDirectory = codexHome.appendingPathComponent("skills/cache-skill", isDirectory: true)
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md", isDirectory: false)

        try createSkill(
            at: skillDirectory,
            body: """
            # Cache Skill

            First description.
            """
        )

        let service = SkillCatalogService(codexHomeURL: codexHome, agentsHomeURL: agentsHome)

        let first = try service.discoverSkills(projectPath: project.path)
        XCTAssertEqual(first.first(where: { $0.name == "Cache Skill" })?.description, "First description.")

        // Keep this >1s so file mtime advances on filesystems with coarse timestamp precision.
        Thread.sleep(forTimeInterval: 1.1)
        try """
        # Cache Skill

        Updated description.
        """.write(to: skillFile, atomically: true, encoding: .utf8)

        let second = try service.discoverSkills(projectPath: project.path)
        XCTAssertEqual(second.first(where: { $0.name == "Cache Skill" })?.description, "Updated description.")
    }

    func testTrustedSourceDetection() {
        let service = SkillCatalogService(
            processRunner: { _, _ in "" }
        )

        XCTAssertTrue(service.isTrustedSource("https://github.com/openai/example-skill"))
        XCTAssertTrue(service.isTrustedSource("/tmp/local-skill"))
        XCTAssertFalse(service.isTrustedSource("https://unknown.example.com/skill"))
        XCTAssertFalse(service.isTrustedSource("git@unknown.example.com:owner/skill.git"))
    }

    func testInstallSkillRejectsUntrustedSourceWithoutConfirmation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-untrusted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = SkillCatalogService(
            codexHomeURL: root.appendingPathComponent(".codex", isDirectory: true),
            agentsHomeURL: root.appendingPathComponent(".agents", isDirectory: true),
            processRunner: { _, _ in
                XCTFail("Process runner should not execute for untrusted source without confirmation")
                return ""
            }
        )

        XCTAssertThrowsError(
            try service.installSkill(
                SkillInstallRequest(
                    source: "https://unknown.example.com/skill.git",
                    scope: .global,
                    projectPath: nil,
                    installer: .git
                )
            )
        ) { error in
            guard case SkillCatalogError.untrustedSourceRequiresConfirmation = error else {
                return XCTFail("Expected untrusted source confirmation error, got \(error)")
            }
        }
    }

    func testGitInstallSupportsPinnedRefAndPersistsMetadata() throws {
        final class InvocationCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var invocations: [[String]] = []

            func append(_ argv: [String]) {
                lock.lock()
                invocations.append(argv)
                lock.unlock()
            }

            func all() -> [[String]] {
                lock.lock()
                defer { lock.unlock() }
                return invocations
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-pin-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let capture = InvocationCapture()
        let service = SkillCatalogService(
            codexHomeURL: codexHome,
            agentsHomeURL: root.appendingPathComponent(".agents", isDirectory: true),
            processRunner: { argv, _ in
                capture.append(argv)
                if argv.prefix(4) == ["git", "clone", "--depth", "1"], let destination = argv.last {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: destination, isDirectory: true),
                        withIntermediateDirectories: true
                    )
                }
                return "ok"
            }
        )

        let result = try service.installSkill(
            SkillInstallRequest(
                source: "https://github.com/example/pinned-skill.git#v1.2.3",
                scope: .global,
                projectPath: nil,
                installer: .git
            )
        )

        let invocations = capture.all()
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0], [
            "git",
            "clone",
            "--depth",
            "1",
            "https://github.com/example/pinned-skill.git",
            result.installedPath,
        ])
        XCTAssertEqual(invocations[1], [
            "git",
            "-C",
            result.installedPath,
            "checkout",
            "--detach",
            "v1.2.3",
        ])

        let metadataURL = URL(fileURLWithPath: result.installedPath, isDirectory: true)
            .appendingPathComponent(".codexchat-install.json", isDirectory: false)
        let metadataText = try String(contentsOf: metadataURL, encoding: .utf8)
        XCTAssertTrue(metadataText.contains("\"pinnedRef\" : \"v1.2.3\""))
    }

    func testUpdateSkillWithPinnedRefUsesFetchAndDetachedCheckout() throws {
        final class InvocationCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var invocations: [[String]] = []

            func append(_ argv: [String]) {
                lock.lock()
                invocations.append(argv)
                lock.unlock()
            }

            func all() -> [[String]] {
                lock.lock()
                defer { lock.unlock() }
                return invocations
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-pin-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = root.appendingPathComponent("skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: skillDirectory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "source" : "https://github.com/example/pinned-skill.git",
          "installer" : "git",
          "pinnedRef" : "release-2026",
          "installedAt" : "2026-02-20T00:00:00Z",
          "updatedAt" : null
        }
        """.write(
            to: skillDirectory.appendingPathComponent(".codexchat-install.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let capture = InvocationCapture()
        let service = SkillCatalogService(
            codexHomeURL: root.appendingPathComponent(".codex", isDirectory: true),
            agentsHomeURL: root.appendingPathComponent(".agents", isDirectory: true),
            processRunner: { argv, _ in
                capture.append(argv)
                return "ok"
            }
        )

        _ = try service.updateSkill(at: skillDirectory.path)
        let invocations = capture.all()
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0], ["git", "-C", skillDirectory.path, "fetch", "--depth", "1", "origin", "release-2026"])
        XCTAssertEqual(invocations[1], ["git", "-C", skillDirectory.path, "checkout", "--detach", "FETCH_HEAD"])
    }

    func testInstallSkillSanitizesDestinationName() throws {
        final class ArgvCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var argv: [String] = []

            func set(_ argv: [String]) {
                lock.lock()
                self.argv = argv
                lock.unlock()
            }

            func get() -> [String] {
                lock.lock()
                defer { lock.unlock() }
                return argv
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let capturedArgv = ArgvCapture()

        let service = SkillCatalogService(
            codexHomeURL: codexHome,
            agentsHomeURL: root.appendingPathComponent(".agents", isDirectory: true),
            processRunner: { argv, _ in
                capturedArgv.set(argv)
                return "ok"
            }
        )

        let result = try service.installSkill(
            SkillInstallRequest(
                source: "../..",
                scope: .global,
                projectPath: nil,
                installer: .git
            )
        )

        let argv = capturedArgv.get()
        XCTAssertEqual(argv.prefix(3), ["git", "clone", "--depth"])
        XCTAssertTrue(result.installedPath.hasPrefix(codexHome.appendingPathComponent("skills", isDirectory: true).path))
        XCTAssertFalse(result.installedPath.contains("/../"))
        XCTAssertNotEqual(URL(fileURLWithPath: result.installedPath).lastPathComponent, "..")
        XCTAssertNotEqual(URL(fileURLWithPath: result.installedPath).lastPathComponent, ".")
    }

    func testRemoteJSONSkillCatalogProviderParsesDirectWrappedAndSkillsAPIPayloads() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directURL = root.appendingPathComponent("direct.json", isDirectory: false)
        try """
        [
          {
            "id": "skill.browser",
            "name": "Agent Browser",
            "summary": "Automate browser workflows",
            "repositoryURL": "https://github.com/example/agent-browser",
            "installSource": "https://github.com/example/agent-browser.git",
            "rank": 0.9
          }
        ]
        """.write(to: directURL, atomically: true, encoding: .utf8)

        let wrappedURL = root.appendingPathComponent("wrapped.json", isDirectory: false)
        try """
        {
          "skills": [
            {
              "id": "skill.docs",
              "name": "OpenAI Docs",
              "summary": "Find OpenAI docs",
              "repositoryURL": "https://github.com/example/openai-docs",
              "installSource": "https://github.com/example/openai-docs.git",
              "rank": 0.7
            }
          ]
        }
        """.write(to: wrappedURL, atomically: true, encoding: .utf8)

        let skillsAPIURL = root.appendingPathComponent("skills-api.json", isDirectory: false)
        try """
        {
          "skills": [
            {
              "source": "vercel-labs/skills",
              "skillId": "find-skills",
              "name": "find-skills",
              "installs": 12345
            }
          ],
          "total": 1,
          "hasMore": false,
          "page": 0
        }
        """.write(to: skillsAPIURL, atomically: true, encoding: .utf8)

        let directProvider = RemoteJSONSkillCatalogProvider(indexURL: directURL)
        let wrappedProvider = RemoteJSONSkillCatalogProvider(indexURL: wrappedURL)
        let skillsAPIProvider = RemoteJSONSkillCatalogProvider(indexURL: skillsAPIURL)

        let direct = try await directProvider.listAvailableSkills()
        let wrapped = try await wrappedProvider.listAvailableSkills()
        let skillsAPI = try await skillsAPIProvider.listAvailableSkills()

        XCTAssertEqual(direct.count, 1)
        XCTAssertEqual(direct.first?.id, "skill.browser")
        XCTAssertEqual(wrapped.count, 1)
        XCTAssertEqual(wrapped.first?.id, "skill.docs")
        XCTAssertEqual(skillsAPI.count, 1)
        XCTAssertEqual(skillsAPI.first?.id, "vercel-labs/skills/find-skills")
        XCTAssertEqual(skillsAPI.first?.repositoryURL, "https://github.com/vercel-labs/skills")
        XCTAssertEqual(skillsAPI.first?.installSource, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(skillsAPI.first?.rank, 12345)
    }

    func testUpdateCapabilityClassification() {
        let service = SkillCatalogService(processRunner: { _, _ in "" })

        let gitSkill = DiscoveredSkill(
            name: "git-skill",
            description: "Git backed",
            scope: .global,
            skillPath: "/tmp/skills/git-skill",
            skillDefinitionPath: "/tmp/skills/git-skill/SKILL.md",
            hasScripts: false,
            sourceURL: "https://github.com/example/git-skill.git",
            optionalMetadata: [:],
            installMetadata: nil,
            isGitRepository: true
        )
        let gitCapability = service.updateCapability(for: gitSkill)
        XCTAssertEqual(gitCapability.kind, .gitUpdate)

        let reinstallSkill = DiscoveredSkill(
            name: "reinstall-skill",
            description: "Reinstall supported",
            scope: .global,
            skillPath: "/tmp/skills/reinstall-skill",
            skillDefinitionPath: "/tmp/skills/reinstall-skill/SKILL.md",
            hasScripts: false,
            sourceURL: nil,
            optionalMetadata: [:],
            installMetadata: SkillInstallMetadata(
                source: "https://github.com/example/reinstall.git",
                installer: .npx
            ),
            isGitRepository: false
        )
        let reinstallCapability = service.updateCapability(for: reinstallSkill)
        XCTAssertEqual(reinstallCapability.kind, .reinstall)
        XCTAssertEqual(reinstallCapability.installer, .npx)

        let unavailable = DiscoveredSkill(
            name: "unavailable-skill",
            description: "No metadata",
            scope: .global,
            skillPath: "/tmp/skills/unavailable-skill",
            skillDefinitionPath: "/tmp/skills/unavailable-skill/SKILL.md",
            hasScripts: false,
            sourceURL: nil,
            optionalMetadata: [:],
            installMetadata: nil,
            isGitRepository: false
        )
        let unavailableCapability = service.updateCapability(for: unavailable)
        XCTAssertEqual(unavailableCapability.kind, .unavailable)
    }

    func testNpxInstallInfersInstalledDirectoryAndWritesMetadata() throws {
        final class RunnerState: @unchecked Sendable {
            private let lock = NSLock()
            var installRoot: String?

            func setInstallRoot(_ path: String) {
                lock.lock()
                installRoot = path
                lock.unlock()
            }

            func getInstallRoot() -> String? {
                lock.lock()
                defer { lock.unlock() }
                return installRoot
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-npx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let state = RunnerState()
        let source = "https://github.com/example/my-skill.git"
        let expectedName = "my-skill"

        let service = SkillCatalogService(
            codexHomeURL: codexHome,
            agentsHomeURL: root.appendingPathComponent(".agents", isDirectory: true),
            processRunner: { argv, cwd in
                if argv == ["npx", "--version"] {
                    return "10.0.0"
                }
                if argv == ["npx", "skills", "add", source], let cwd {
                    state.setInstallRoot(cwd)
                    let installed = URL(fileURLWithPath: cwd, isDirectory: true)
                        .appendingPathComponent(expectedName, isDirectory: true)
                    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
                    try "# My Skill".write(
                        to: installed.appendingPathComponent("SKILL.md", isDirectory: false),
                        atomically: true,
                        encoding: .utf8
                    )
                    return "installed"
                }
                return ""
            }
        )

        let result = try service.installSkill(
            SkillInstallRequest(
                source: source,
                scope: .global,
                projectPath: nil,
                installer: .npx
            )
        )

        XCTAssertEqual(result.installedPath, try URL(fileURLWithPath: XCTUnwrap(state.getInstallRoot()), isDirectory: true).appendingPathComponent(expectedName, isDirectory: true).path)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: result.installedPath, isDirectory: true)
                    .appendingPathComponent(".codexchat-install.json", isDirectory: false).path
            )
        )
    }

    func testReinstallRollsBackWhenAtomicReplaceFailsMidSwap() throws {
        final class FailingSecondMoveFileManager: FileManager, @unchecked Sendable {
            private let lock = NSLock()
            private var moveCount = 0
            let failDestinationLastPathComponent: String

            init(failDestinationLastPathComponent: String) {
                self.failDestinationLastPathComponent = failDestinationLastPathComponent
                super.init()
            }

            override func moveItem(at srcURL: URL, to dstURL: URL) throws {
                lock.lock()
                moveCount += 1
                let currentMoveCount = moveCount
                lock.unlock()

                if currentMoveCount == 2, dstURL.lastPathComponent == failDestinationLastPathComponent {
                    throw NSError(
                        domain: "CodexSkillsTests",
                        code: 42,
                        userInfo: [NSLocalizedDescriptionKey: "Injected swap failure"]
                    )
                }

                try super.moveItem(at: srcURL, to: dstURL)
            }
        }

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexskills-reinstall-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let codexHome = base.appendingPathComponent(".codex", isDirectory: true)
        let skillDirectory = codexHome.appendingPathComponent("skills/rollback-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "old-content".write(
            to: skillDirectory.appendingPathComponent("SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let fileManager = FailingSecondMoveFileManager(failDestinationLastPathComponent: "rollback-skill")
        let source = "https://github.com/example/rollback-skill.git"
        let service = SkillCatalogService(
            fileManager: fileManager,
            codexHomeURL: codexHome,
            agentsHomeURL: base.appendingPathComponent(".agents", isDirectory: true),
            processRunner: { argv, _ in
                if argv.count >= 6, argv[0] == "git", argv[1] == "clone", argv[4] == source {
                    let destination = URL(fileURLWithPath: argv[5], isDirectory: true)
                    try "# New Skill\n".write(
                        to: destination.appendingPathComponent("SKILL.md", isDirectory: false),
                        atomically: true,
                        encoding: .utf8
                    )
                    return "cloned"
                }
                return ""
            }
        )

        let discovered = DiscoveredSkill(
            name: "rollback-skill",
            description: "test",
            scope: .global,
            skillPath: skillDirectory.path,
            skillDefinitionPath: skillDirectory.appendingPathComponent("SKILL.md", isDirectory: false).path,
            hasScripts: false,
            sourceURL: nil,
            optionalMetadata: [:],
            installMetadata: SkillInstallMetadata(source: source, installer: .git),
            isGitRepository: false
        )

        XCTAssertThrowsError(try service.reinstallSkill(discovered))

        let restoredContent = try String(
            contentsOf: skillDirectory.appendingPathComponent("SKILL.md", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertEqual(restoredContent, "old-content")
    }

    func testDefaultProcessRunnerTimesOutWhenConfigured() throws {
        try withEnvironment("CODEX_PROCESS_TIMEOUT_MS", "100") {
            XCTAssertThrowsError(
                try SkillCatalogService.defaultProcessRunner(
                    ["sh", "-c", "sleep 1"],
                    nil
                )
            ) { error in
                guard case let SkillCatalogError.commandFailed(_, output) = error else {
                    return XCTFail("Expected commandFailed, got \(error)")
                }
                XCTAssertTrue(output.contains("Timed out"))
            }
        }
    }

    func testDefaultProcessRunnerTruncatesOutputWhenConfigured() throws {
        try withEnvironment("CODEX_PROCESS_MAX_OUTPUT_BYTES", "1024") {
            let output = try SkillCatalogService.defaultProcessRunner(
                ["perl", "-e", "print 'x' x 5000"],
                nil
            )

            XCTAssertTrue(output.contains("[output truncated after 1024 bytes]"))
        }
    }

    private func withEnvironment(
        _ key: String,
        _ value: String,
        body: () throws -> Void
    ) rethrows {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try body()
    }

    private func createSkill(at directoryURL: URL, body: String, includeScripts: Bool = false) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let skillFile = directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
        try body.write(to: skillFile, atomically: true, encoding: .utf8)
        if includeScripts {
            try FileManager.default.createDirectory(
                at: directoryURL.appendingPathComponent("scripts", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }
}
