import Foundation

public protocol ProjectRepository: Sendable {
    func listProjects() async throws -> [ProjectRecord]
    func getProject(id: UUID) async throws -> ProjectRecord?
    func createProject(named name: String) async throws -> ProjectRecord
    func updateProjectName(id: UUID, name: String) async throws -> ProjectRecord
}

public protocol ThreadRepository: Sendable {
    func listThreads(projectID: UUID) async throws -> [ThreadRecord]
    func getThread(id: UUID) async throws -> ThreadRecord?
    func createThread(projectID: UUID, title: String) async throws -> ThreadRecord
    func updateThreadTitle(id: UUID, title: String) async throws -> ThreadRecord
}

public protocol PreferenceRepository: Sendable {
    func setPreference(key: AppPreferenceKey, value: String) async throws
    func getPreference(key: AppPreferenceKey) async throws -> String?
}

public protocol RuntimeThreadMappingRepository: Sendable {
    func setRuntimeThreadID(localThreadID: UUID, runtimeThreadID: String) async throws
    func getRuntimeThreadID(localThreadID: UUID) async throws -> String?
}

public protocol ProjectSecretRepository: Sendable {
    func listSecrets(projectID: UUID) async throws -> [ProjectSecretRecord]
    func upsertSecret(projectID: UUID, name: String, keychainAccount: String) async throws -> ProjectSecretRecord
    func deleteSecret(id: UUID) async throws
}
