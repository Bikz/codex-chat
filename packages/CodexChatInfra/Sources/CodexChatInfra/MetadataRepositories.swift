import CodexChatCore
import GRDB

public struct MetadataRepositories: Sendable {
    public let projectRepository: any ProjectRepository
    public let threadRepository: any ThreadRepository
    public let preferenceRepository: any PreferenceRepository
    public let runtimeThreadMappingRepository: any RuntimeThreadMappingRepository
    public let followUpQueueRepository: any FollowUpQueueRepository
    public let projectSecretRepository: any ProjectSecretRepository
    public let projectSkillEnablementRepository: any ProjectSkillEnablementRepository
    public let chatSearchRepository: any ChatSearchRepository

    public init(database: MetadataDatabase) {
        projectRepository = SQLiteProjectRepository(dbQueue: database.dbQueue)
        threadRepository = SQLiteThreadRepository(dbQueue: database.dbQueue)
        preferenceRepository = SQLitePreferenceRepository(dbQueue: database.dbQueue)
        runtimeThreadMappingRepository = SQLiteRuntimeThreadMappingRepository(dbQueue: database.dbQueue)
        followUpQueueRepository = SQLiteFollowUpQueueRepository(dbQueue: database.dbQueue)
        projectSecretRepository = SQLiteProjectSecretRepository(dbQueue: database.dbQueue)
        projectSkillEnablementRepository = SQLiteProjectSkillEnablementRepository(dbQueue: database.dbQueue)
        chatSearchRepository = SQLiteChatSearchRepository(dbQueue: database.dbQueue)
    }
}
