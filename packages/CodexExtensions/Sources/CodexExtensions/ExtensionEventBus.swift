import Foundation

public actor ExtensionEventBus {
    private let streamStorage: AsyncStream<ExtensionEventEnvelope>
    private let continuation: AsyncStream<ExtensionEventEnvelope>.Continuation

    public init(bufferLimit: Int = 256) {
        var created: AsyncStream<ExtensionEventEnvelope>.Continuation?
        streamStorage = AsyncStream(bufferingPolicy: .bufferingNewest(bufferLimit)) { continuation in
            created = continuation
        }
        continuation = created!
    }

    public func publish(_ event: ExtensionEventEnvelope) {
        continuation.yield(event)
    }

    public func stream() -> AsyncStream<ExtensionEventEnvelope> {
        streamStorage
    }
}
