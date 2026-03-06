import CodexChatCore
import CodexMods
import Foundation

extension AppModel {
    nonisolated static func normalizedModDirectoryPath(_ path: String) -> String {
        NSString(string: path).standardizingPath
    }

    nonisolated static func isReservedFirstPartyModID(_ id: String) -> Bool {
        FirstPartyModTrust.usesReservedNamespace(id)
    }

    nonisolated static func isFirstPartyModFixturePath(_ path: String) -> Bool {
        FirstPartyModTrust.isFirstPartyDirectoryPath(normalizedModDirectoryPath(path))
    }

    nonisolated static func isFirstPartyModSource(_ source: String?) -> Bool {
        FirstPartyModTrust.isVettedFirstPartySource(source)
    }

    nonisolated static func vettedFirstPartyInstalledPaths(
        from installRecords: [ExtensionInstallRecord]
    ) -> Set<String> {
        Set(
            installRecords.compactMap { record in
                guard isFirstPartyModSource(record.sourceURL) || isFirstPartyModFixturePath(record.installedPath) else {
                    return nil
                }
                return normalizedModDirectoryPath(record.installedPath)
            }
        )
    }

    nonisolated static func matchingInstallRecord(
        for mod: DiscoveredUIMod,
        scope: ExtensionInstallScope,
        projectID: UUID?,
        installRecords: [ExtensionInstallRecord]
    ) -> ExtensionInstallRecord? {
        let normalizedPath = normalizedModDirectoryPath(mod.directoryPath)
        let scopedRecords = installRecords.filter { record in
            guard record.scope == scope else {
                return false
            }
            if scope == .project {
                return record.projectID == projectID
            }
            return true
        }

        if let exactPathMatch = scopedRecords.first(where: {
            normalizedModDirectoryPath($0.installedPath) == normalizedPath
        }) {
            return exactPathMatch
        }

        return scopedRecords.first(where: { $0.modID == mod.definition.manifest.id })
    }

    nonisolated static func syntheticExtensionInstallID(
        scope: ExtensionInstallScope,
        projectID: UUID?,
        modID: String
    ) -> String {
        switch scope {
        case .global:
            return "global:\(modID)"
        case .project:
            let projectKey = projectID?.uuidString.lowercased() ?? "unknown-project"
            return "project:\(projectKey):\(modID)"
        }
    }

    nonisolated static func runtimeAutomationID(installID: String, automationID: String) -> String {
        "\(installID)::\(automationID)"
    }

    func isVettedFirstPartyMod(_ mod: DiscoveredUIMod, source: String? = nil) -> Bool {
        let normalizedPath = Self.normalizedModDirectoryPath(mod.directoryPath)
        return Self.isFirstPartyModFixturePath(normalizedPath)
            || Self.isFirstPartyModSource(source)
            || vettedFirstPartyModDirectoryPaths.contains(normalizedPath)
    }

    func isVettedFirstPartyMod(_ mod: DiscoveredUIMod, installRecord: ExtensionInstallRecord?) -> Bool {
        isVettedFirstPartyMod(mod, source: installRecord?.sourceURL)
    }
}
