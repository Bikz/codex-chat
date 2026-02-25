import Foundation

struct RemoteControlPairRequestPrompt: Identifiable, Equatable, Sendable {
    let requestID: String
    let requesterIP: String?
    let requestedAt: Date?
    let expiresAt: Date?

    var id: String {
        requestID
    }
}
