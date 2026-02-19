import Foundation

public enum ThreadListScope: String, Sendable, Hashable, Codable {
    case active
    case archived
    case all
}

public protocol ProjectRepository: Sendable {
    func listProjects() async throws -> [ProjectRecord]
    func getProject(id: UUID) async throws -> ProjectRecord?
    func getProject(path: String) async throws -> ProjectRecord?
    func createProject(named name: String, path: String, trustState: ProjectTrustState, isGeneralProject: Bool) async throws -> ProjectRecord
    func deleteProject(id: UUID) async throws
    func updateProjectName(id: UUID, name: String) async throws -> ProjectRecord
    func updateProjectPath(id: UUID, path: String) async throws -> ProjectRecord
    func updateProjectTrustState(id: UUID, trustState: ProjectTrustState) async throws -> ProjectRecord
    func updateProjectSafetySettings(id: UUID, settings: ProjectSafetySettings) async throws -> ProjectRecord
    func updateProjectMemorySettings(id: UUID, settings: ProjectMemorySettings) async throws -> ProjectRecord
    func updateProjectUIModPath(id: UUID, uiModPath: String?) async throws -> ProjectRecord
}

public protocol ThreadRepository: Sendable {
    func listThreads(projectID: UUID, scope: ThreadListScope) async throws -> [ThreadRecord]
    func listArchivedThreads() async throws -> [ThreadRecord]
    func getThread(id: UUID) async throws -> ThreadRecord?
    func createThread(projectID: UUID, title: String) async throws -> ThreadRecord
    func updateThreadTitle(id: UUID, title: String) async throws -> ThreadRecord
    func setThreadPinned(id: UUID, isPinned: Bool) async throws -> ThreadRecord
    func archiveThread(id: UUID, archivedAt: Date) async throws -> ThreadRecord
    func unarchiveThread(id: UUID) async throws -> ThreadRecord
    func touchThread(id: UUID) async throws -> ThreadRecord
}

public extension ThreadRepository {
    func listThreads(projectID: UUID) async throws -> [ThreadRecord] {
        try await listThreads(projectID: projectID, scope: .active)
    }
}

public protocol PreferenceRepository: Sendable {
    func setPreference(key: AppPreferenceKey, value: String) async throws
    func getPreference(key: AppPreferenceKey) async throws -> String?
}

public protocol RuntimeThreadMappingRepository: Sendable {
    func setRuntimeThreadID(localThreadID: UUID, runtimeThreadID: String) async throws
    func getRuntimeThreadID(localThreadID: UUID) async throws -> String?
    func getLocalThreadID(runtimeThreadID: String) async throws -> UUID?
}

public protocol FollowUpQueueRepository: Sendable {
    func list(threadID: UUID) async throws -> [FollowUpQueueItemRecord]
    func listNextAutoCandidate(preferredThreadID: UUID?) async throws -> FollowUpQueueItemRecord?
    func enqueue(_ item: FollowUpQueueItemRecord) async throws
    func updateText(id: UUID, text: String) async throws -> FollowUpQueueItemRecord
    func move(id: UUID, threadID: UUID, toSortIndex: Int) async throws
    func updateDispatchMode(id: UUID, mode: FollowUpDispatchMode) async throws -> FollowUpQueueItemRecord
    func markFailed(id: UUID, error: String) async throws
    func markPending(id: UUID) async throws
    func delete(id: UUID) async throws
}

public protocol ProjectSecretRepository: Sendable {
    func listSecrets(projectID: UUID) async throws -> [ProjectSecretRecord]
    func upsertSecret(projectID: UUID, name: String, keychainAccount: String) async throws -> ProjectSecretRecord
    func deleteSecret(id: UUID) async throws
}

public protocol ProjectSkillEnablementRepository: Sendable {
    func setSkillEnabled(target: SkillEnablementTarget, projectID: UUID?, skillPath: String, enabled: Bool) async throws
    func isSkillEnabled(target: SkillEnablementTarget, projectID: UUID?, skillPath: String) async throws -> Bool
    func enabledSkillPaths(target: SkillEnablementTarget, projectID: UUID?) async throws -> Set<String>
    func resolvedEnabledSkillPaths(forProjectID projectID: UUID?, generalProjectID: UUID?) async throws -> Set<String>
    func rewriteSkillPaths(fromRootPath: String, toRootPath: String) async throws

    func setSkillEnabled(projectID: UUID, skillPath: String, enabled: Bool) async throws
    func isSkillEnabled(projectID: UUID, skillPath: String) async throws -> Bool
    func enabledSkillPaths(projectID: UUID) async throws -> Set<String>
    func rewriteSkillPaths(projectID: UUID, fromRootPath: String, toRootPath: String) async throws
}

public protocol ChatSearchRepository: Sendable {
    func indexThreadTitle(threadID: UUID, projectID: UUID, title: String) async throws
    func indexMessageExcerpt(threadID: UUID, projectID: UUID, text: String) async throws
    func search(query: String, projectID: UUID?, limit: Int) async throws -> [ChatSearchResult]
}

public protocol ExtensionInstallRepository: Sendable {
    func list() async throws -> [ExtensionInstallRecord]
    func upsert(_ record: ExtensionInstallRecord) async throws -> ExtensionInstallRecord
    func delete(id: String) async throws
}

public protocol ExtensionPermissionRepository: Sendable {
    func list(modID: String) async throws -> [ExtensionPermissionRecord]
    func set(modID: String, permissionKey: ExtensionPermissionKey, status: ExtensionPermissionStatus, grantedAt: Date) async throws
}

public protocol ExtensionHookStateRepository: Sendable {
    func list(modID: String) async throws -> [ExtensionHookStateRecord]
    func upsert(_ record: ExtensionHookStateRecord) async throws -> ExtensionHookStateRecord
}

public protocol ExtensionAutomationStateRepository: Sendable {
    func list(modID: String) async throws -> [ExtensionAutomationStateRecord]
    func upsert(_ record: ExtensionAutomationStateRecord) async throws -> ExtensionAutomationStateRecord
}

public protocol ComputerActionPermissionRepository: Sendable {
    func list(projectID: UUID?) async throws -> [ComputerActionPermissionRecord]
    func get(actionID: String, projectID: UUID?) async throws -> ComputerActionPermissionRecord?
    func set(
        actionID: String,
        projectID: UUID?,
        decision: ComputerActionPermissionDecision,
        decidedAt: Date
    ) async throws -> ComputerActionPermissionRecord
}

public protocol ComputerActionRunRepository: Sendable {
    func list(threadID: UUID?) async throws -> [ComputerActionRunRecord]
    func list(runContextID: String) async throws -> [ComputerActionRunRecord]
    func upsert(_ record: ComputerActionRunRecord) async throws -> ComputerActionRunRecord
    func latest(runContextID: String) async throws -> ComputerActionRunRecord?
}

public protocol PlanRunRepository: Sendable {
    func list(threadID: UUID) async throws -> [PlanRunRecord]
    func get(id: UUID) async throws -> PlanRunRecord?
    func upsert(_ record: PlanRunRecord) async throws -> PlanRunRecord
    func delete(id: UUID) async throws
}

public protocol PlanRunTaskRepository: Sendable {
    func list(planRunID: UUID) async throws -> [PlanRunTaskRecord]
    func upsert(_ record: PlanRunTaskRecord) async throws -> PlanRunTaskRecord
    func replace(planRunID: UUID, tasks: [PlanRunTaskRecord]) async throws
}
