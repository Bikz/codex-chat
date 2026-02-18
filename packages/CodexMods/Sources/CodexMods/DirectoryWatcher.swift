import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public final class DirectoryWatcher: @unchecked Sendable {
    private let path: String
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    public init(path: String, queue: DispatchQueue? = nil, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.queue = queue ?? DispatchQueue(label: "codexmods.dirwatch.\(UUID().uuidString)")
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard source == nil else { return }

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        self.descriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
