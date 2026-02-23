import CryptoKit
import Foundation

public enum ModPermissionKey: String, CaseIterable, Hashable, Sendable, Codable {
    case projectRead
    case projectWrite
    case network
    case runtimeControl
    case runWhenAppClosed
}

public struct ModEntrypoints: Hashable, Sendable, Codable {
    public var uiMod: String

    public init(uiMod: String = "ui.mod.json") {
        self.uiMod = uiMod
    }
}

public struct ModCompatibility: Hashable, Sendable, Codable {
    public var platforms: [String]
    public var minCodexChatVersion: String?
    public var maxCodexChatVersion: String?

    public init(
        platforms: [String] = ["macos"],
        minCodexChatVersion: String? = nil,
        maxCodexChatVersion: String? = nil
    ) {
        self.platforms = platforms
        self.minCodexChatVersion = minCodexChatVersion
        self.maxCodexChatVersion = maxCodexChatVersion
    }
}

public struct ModIntegrity: Hashable, Sendable, Codable {
    public var uiModSha256: String?

    public init(uiModSha256: String? = nil) {
        self.uiModSha256 = uiModSha256
    }
}

public struct ModPackageManifest: Hashable, Sendable, Codable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var author: String?
    public var license: String?
    public var homepage: String?
    public var repository: String?
    public var entrypoints: ModEntrypoints
    public var permissions: [ModPermissionKey]
    public var compatibility: ModCompatibility?
    public var integrity: ModIntegrity?

    public init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        author: String? = nil,
        license: String? = nil,
        homepage: String? = nil,
        repository: String? = nil,
        entrypoints: ModEntrypoints = .init(),
        permissions: [ModPermissionKey] = [],
        compatibility: ModCompatibility? = nil,
        integrity: ModIntegrity? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.license = license
        self.homepage = homepage
        self.repository = repository
        self.entrypoints = entrypoints
        self.permissions = permissions
        self.compatibility = compatibility
        self.integrity = integrity
    }
}

public enum ModPackageManifestSource: String, Hashable, Sendable {
    case codexManifest
    case derivedFromUIMod
}

public struct ResolvedModPackage: Hashable, Sendable {
    public var manifestSource: ModPackageManifestSource
    public var manifest: ModPackageManifest
    public var uiModDefinition: UIModDefinition
    public var packageRootPath: String
    public var uiModPath: String
    public var requestedPermissions: Set<ModPermissionKey>
    public var warnings: [String]

    public init(
        manifestSource: ModPackageManifestSource,
        manifest: ModPackageManifest,
        uiModDefinition: UIModDefinition,
        packageRootPath: String,
        uiModPath: String,
        requestedPermissions: Set<ModPermissionKey>,
        warnings: [String]
    ) {
        self.manifestSource = manifestSource
        self.manifest = manifest
        self.uiModDefinition = uiModDefinition
        self.packageRootPath = packageRootPath
        self.uiModPath = uiModPath
        self.requestedPermissions = requestedPermissions
        self.warnings = warnings
    }
}

public enum ModPackageValidationError: LocalizedError, Sendable {
    case missingPackageManifest
    case unsupportedSchemaVersion(Int)
    case unsupportedUIModSchemaVersion(Int)
    case invalidPackageID(String)
    case invalidPackageVersion(String)
    case invalidEntrypointPath(String)
    case missingEntrypoint(String)
    case invalidManifest(String)
    case invalidUIModDefinition(String)
    case manifestMismatch(field: String, expected: String, actual: String)
    case permissionsUndeclared([ModPermissionKey])
    case incompatiblePlatform([String])
    case invalidCompatibilityVersion(field: String, value: String)
    case integrityMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingPackageManifest:
            "Missing codex.mod.json. CodexChat now requires codex.mod.json for install. Add codex.mod.json (schemaVersion 1) and reinstall."
        case let .unsupportedSchemaVersion(version):
            "Unsupported mod package schemaVersion: \(version)"
        case let .unsupportedUIModSchemaVersion(version):
            "Unsupported ui.mod.json schemaVersion \(version). CodexChat now supports schemaVersion 1 only."
        case let .invalidPackageID(id):
            "Invalid mod package id: \(id)"
        case let .invalidPackageVersion(version):
            "Invalid mod package version: \(version)"
        case let .invalidEntrypointPath(path):
            "Invalid package entrypoint path: \(path)"
        case let .missingEntrypoint(path):
            "Package entrypoint not found: \(path)"
        case let .invalidManifest(detail):
            "Invalid codex.mod.json: \(detail)"
        case let .invalidUIModDefinition(detail):
            "Invalid ui.mod.json: \(detail)"
        case let .manifestMismatch(field, expected, actual):
            "Manifest mismatch for \(field): expected \(expected), got \(actual)"
        case let .permissionsUndeclared(missing):
            "Package permissions do not declare all runtime permissions: \(missing.map(\.rawValue).joined(separator: ", "))"
        case let .incompatiblePlatform(platforms):
            "This mod package does not declare compatibility with macOS: \(platforms.joined(separator: ", "))"
        case let .invalidCompatibilityVersion(field, value):
            "Invalid compatibility \(field) version: \(value). Expected semver (for example 1.2.3)."
        case let .integrityMismatch(expected, actual):
            "ui.mod.json checksum mismatch. Expected \(expected), got \(actual)."
        }
    }
}

public enum ModPackageManifestLoader {
    public static func load(packageRootURL: URL, fileManager: FileManager = .default) throws -> ResolvedModPackage {
        let normalizedRoot = packageRootURL.standardizedFileURL
        let manifestURL = normalizedRoot.appendingPathComponent("codex.mod.json", isDirectory: false)
        let hasManifest = fileManager.fileExists(atPath: manifestURL.path)
        guard hasManifest else {
            throw ModPackageValidationError.missingPackageManifest
        }

        let packageManifest: ModPackageManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            packageManifest = try JSONDecoder().decode(ModPackageManifest.self, from: data)
        } catch {
            throw ModPackageValidationError.invalidManifest(error.localizedDescription)
        }

        let uiModRelativePath = packageManifest.entrypoints.uiMod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ModPathSafety.normalizedSafeRelativePath(uiModRelativePath) != nil else {
            throw ModPackageValidationError.invalidEntrypointPath(uiModRelativePath)
        }

        let uiModURL = normalizedRoot.appendingPathComponent(uiModRelativePath, isDirectory: false).standardizedFileURL
        guard ModPathSafety.isWithinRoot(candidateURL: uiModURL, rootURL: normalizedRoot) else {
            throw ModPackageValidationError.invalidEntrypointPath(uiModRelativePath)
        }
        guard fileManager.fileExists(atPath: uiModURL.path) else {
            throw ModPackageValidationError.missingEntrypoint(uiModRelativePath)
        }

        let uiModDefinition: UIModDefinition
        do {
            let data = try Data(contentsOf: uiModURL)
            if containsLegacyRightInspectorKey(in: data) {
                throw ModPackageValidationError.invalidUIModDefinition(
                    "`uiSlots.rightInspector` is unsupported. Rename to `uiSlots.modsBar`."
                )
            }
            uiModDefinition = try JSONDecoder().decode(UIModDefinition.self, from: data)
        } catch {
            throw ModPackageValidationError.invalidUIModDefinition(error.localizedDescription)
        }

        guard uiModDefinition.schemaVersion == 1 else {
            throw ModPackageValidationError.unsupportedUIModSchemaVersion(uiModDefinition.schemaVersion)
        }

        let requestedPermissions = Self.requestedPermissions(for: uiModDefinition)

        try validate(packageManifest: packageManifest, uiModDefinition: uiModDefinition, requestedPermissions: requestedPermissions)
        if let checksum = packageManifest.integrity?.uiModSha256?.trimmingCharacters(in: .whitespacesAndNewlines),
           !checksum.isEmpty
        {
            let uiModData = try Data(contentsOf: uiModURL)
            let actual = "sha256:\(sha256Hex(of: uiModData))"
            if normalizedChecksum(checksum) != normalizedChecksum(actual) {
                throw ModPackageValidationError.integrityMismatch(expected: checksum, actual: actual)
            }
        }

        return ResolvedModPackage(
            manifestSource: .codexManifest,
            manifest: packageManifest,
            uiModDefinition: uiModDefinition,
            packageRootPath: normalizedRoot.path,
            uiModPath: uiModURL.path,
            requestedPermissions: requestedPermissions,
            warnings: []
        )
    }

    public static func requestedPermissions(for definition: UIModDefinition) -> Set<ModPermissionKey> {
        var requested = Set<ModPermissionKey>()

        for hook in definition.hooks {
            requested.formUnion(permissionKeys(from: hook.permissions))
        }
        for automation in definition.automations {
            requested.formUnion(permissionKeys(from: automation.permissions))
        }

        return requested
    }

    private static func validate(
        packageManifest: ModPackageManifest,
        uiModDefinition: UIModDefinition,
        requestedPermissions: Set<ModPermissionKey>
    ) throws {
        guard packageManifest.schemaVersion == 1 else {
            throw ModPackageValidationError.unsupportedSchemaVersion(packageManifest.schemaVersion)
        }

        guard isValidPackageID(packageManifest.id) else {
            throw ModPackageValidationError.invalidPackageID(packageManifest.id)
        }
        guard isValidVersion(packageManifest.version) else {
            throw ModPackageValidationError.invalidPackageVersion(packageManifest.version)
        }

        if packageManifest.id != uiModDefinition.manifest.id {
            throw ModPackageValidationError.manifestMismatch(
                field: "id",
                expected: uiModDefinition.manifest.id,
                actual: packageManifest.id
            )
        }
        if packageManifest.name != uiModDefinition.manifest.name {
            throw ModPackageValidationError.manifestMismatch(
                field: "name",
                expected: uiModDefinition.manifest.name,
                actual: packageManifest.name
            )
        }
        if packageManifest.version != uiModDefinition.manifest.version {
            throw ModPackageValidationError.manifestMismatch(
                field: "version",
                expected: uiModDefinition.manifest.version,
                actual: packageManifest.version
            )
        }

        let declaredPermissions = Set(packageManifest.permissions)
        let undeclared = requestedPermissions.subtracting(declaredPermissions)
        if !undeclared.isEmpty {
            throw ModPackageValidationError.permissionsUndeclared(undeclared.sorted { $0.rawValue < $1.rawValue })
        }

        if let compatibility = packageManifest.compatibility {
            if !compatibility.platforms.isEmpty {
                let normalized = Set(compatibility.platforms.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                })
                let supportsMacOS = normalized.contains("macos") || normalized.contains("darwin") || normalized.contains("*")
                if !supportsMacOS {
                    throw ModPackageValidationError.incompatiblePlatform(Array(normalized).sorted())
                }
            }
            if let min = compatibility.minCodexChatVersion,
               !min.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isValidVersion(min)
            {
                throw ModPackageValidationError.invalidCompatibilityVersion(
                    field: "minCodexChatVersion",
                    value: min
                )
            }
            if let max = compatibility.maxCodexChatVersion,
               !max.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isValidVersion(max)
            {
                throw ModPackageValidationError.invalidCompatibilityVersion(
                    field: "maxCodexChatVersion",
                    value: max
                )
            }
        }
    }

    private static func isValidPackageID(_ raw: String) -> Bool {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        return candidate.range(of: "^[a-z0-9]+([._-][a-z0-9]+)*$", options: .regularExpression) != nil
    }

    private static func isValidVersion(_ raw: String) -> Bool {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        return candidate.range(
            of: "^\\d+\\.\\d+\\.\\d+(?:[-+][A-Za-z0-9.-]+)?$",
            options: .regularExpression
        ) != nil
    }

    private static func permissionKeys(from permissions: ModExtensionPermissions) -> Set<ModPermissionKey> {
        var keys = Set<ModPermissionKey>()
        if permissions.projectRead { keys.insert(.projectRead) }
        if permissions.projectWrite { keys.insert(.projectWrite) }
        if permissions.network { keys.insert(.network) }
        if permissions.runtimeControl { keys.insert(.runtimeControl) }
        if permissions.runWhenAppClosed { keys.insert(.runWhenAppClosed) }
        return keys
    }

    private static func normalizedChecksum(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("sha256:") ? trimmed : "sha256:\(trimmed)"
    }

    private static func containsLegacyRightInspectorKey(in definitionData: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: definitionData) as? [String: Any],
            let uiSlots = root["uiSlots"] as? [String: Any]
        else {
            return false
        }

        return uiSlots["rightInspector"] != nil
    }

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
