import Darwin
import Foundation

enum ComputerActionHarnessServerError: LocalizedError {
    case socketPathTooLong
    case failedToCreateSocket(String)
    case failedToBindSocket(String)
    case failedToListen(String)
    case missingParentDirectory

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            "Harness socket path is too long for a UNIX domain socket."
        case let .failedToCreateSocket(detail):
            "Failed to create harness socket: \(detail)"
        case let .failedToBindSocket(detail):
            "Failed to bind harness socket: \(detail)"
        case let .failedToListen(detail):
            "Failed to listen on harness socket: \(detail)"
        case .missingParentDirectory:
            "Harness socket parent directory is missing."
        }
    }
}

final class ComputerActionHarnessServer: @unchecked Sendable {
    typealias RequestHandler = @Sendable (HarnessInvokeRequest) async -> HarnessInvokeResponse
    typealias LogHandler = @Sendable (String) -> Void

    private enum Constants {
        static let maxRequestBytes = 128 * 1024
        static let readBufferSize = 4096
    }

    private let socketPath: String
    private let requestHandler: RequestHandler
    private let logHandler: LogHandler
    private let queue = DispatchQueue(label: "com.codexchat.harness.server")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var serverFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var clientBuffers: [Int32: Data] = [:]

    init(
        socketPath: String,
        requestHandler: @escaping RequestHandler,
        logHandler: @escaping LogHandler = { _ in }
    ) {
        self.socketPath = socketPath
        self.requestHandler = requestHandler
        self.logHandler = logHandler
    }

    func start() throws {
        try queue.sync {
            if serverFileDescriptor != -1 {
                return
            }

            let socketURL = URL(fileURLWithPath: socketPath, isDirectory: false)
            let parentDirectoryURL = socketURL.deletingLastPathComponent()
            guard !parentDirectoryURL.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ComputerActionHarnessServerError.missingParentDirectory
            }

            try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
            _ = Darwin.unlink(socketPath)

            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw ComputerActionHarnessServerError.failedToCreateSocket(Self.systemErrorDescription())
            }

            if fcntl(fd, F_SETFL, O_NONBLOCK) == -1 {
                Darwin.close(fd)
                throw ComputerActionHarnessServerError.failedToCreateSocket(Self.systemErrorDescription())
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = socketPath.utf8CString
            let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= sunPathCapacity else {
                Darwin.close(fd)
                throw ComputerActionHarnessServerError.socketPathTooLong
            }

            withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                bytes.initializeMemory(as: CChar.self, repeating: 0)
                for (index, value) in pathBytes.enumerated() where index < bytes.count {
                    bytes[index] = UInt8(bitPattern: value)
                }
            }

            let addressLength = socklen_t(MemoryLayout.size(ofValue: address))
            let bindResult = withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, addressLength)
                }
            }

            guard bindResult == 0 else {
                Darwin.close(fd)
                throw ComputerActionHarnessServerError.failedToBindSocket(Self.systemErrorDescription())
            }

            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                Darwin.close(fd)
                throw ComputerActionHarnessServerError.failedToListen(Self.systemErrorDescription())
            }

            _ = Darwin.chmod(socketPath, S_IRUSR | S_IWUSR)

            serverFileDescriptor = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptPendingClients()
            }
            source.resume()
            acceptSource = source
        }
    }

    func stop() {
        queue.sync {
            teardownLocked()
        }
    }

    deinit {
        teardownLocked()
    }

    private func teardownLocked() {
        for (clientFileDescriptor, source) in clientSources {
            source.cancel()
            Darwin.close(clientFileDescriptor)
        }
        clientSources.removeAll(keepingCapacity: false)
        clientBuffers.removeAll(keepingCapacity: false)

        acceptSource?.cancel()
        acceptSource = nil

        if serverFileDescriptor != -1 {
            Darwin.close(serverFileDescriptor)
            serverFileDescriptor = -1
        }

        _ = Darwin.unlink(socketPath)
    }

    private func acceptPendingClients() {
        guard serverFileDescriptor != -1 else {
            return
        }

        while true {
            let clientFileDescriptor = Darwin.accept(serverFileDescriptor, nil, nil)
            if clientFileDescriptor == -1 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                logHandler("Harness accept failed: \(Self.systemErrorDescription())")
                return
            }

            if fcntl(clientFileDescriptor, F_SETFL, O_NONBLOCK) == -1 {
                Darwin.close(clientFileDescriptor)
                continue
            }

            let source = DispatchSource.makeReadSource(fileDescriptor: clientFileDescriptor, queue: queue)
            source.setEventHandler { [weak self] in
                self?.readClientData(clientFileDescriptor)
            }
            source.resume()
            clientSources[clientFileDescriptor] = source
            clientBuffers[clientFileDescriptor] = Data()
        }
    }

    private func readClientData(_ clientFileDescriptor: Int32) {
        var readBuffer = [UInt8](repeating: 0, count: Constants.readBufferSize)

        while true {
            let bytesRead = Darwin.read(clientFileDescriptor, &readBuffer, readBuffer.count)

            if bytesRead > 0 {
                clientBuffers[clientFileDescriptor, default: Data()]
                    .append(readBuffer, count: bytesRead)

                guard let buffered = clientBuffers[clientFileDescriptor] else {
                    closeClient(clientFileDescriptor)
                    return
                }

                if buffered.count > Constants.maxRequestBytes {
                    sendResponse(
                        HarnessInvokeResponse(
                            requestID: "",
                            status: .invalid,
                            summary: "Request exceeded maximum size.",
                            errorCode: "request_too_large",
                            errorMessage: "Harness request exceeded max bytes."
                        ),
                        to: clientFileDescriptor
                    )
                    closeClient(clientFileDescriptor)
                    return
                }

                guard let newlineIndex = buffered.firstIndex(of: 0x0A) else {
                    if bytesRead < readBuffer.count {
                        return
                    }
                    continue
                }

                let lineData = buffered.prefix(upTo: newlineIndex)
                clientBuffers[clientFileDescriptor] = Data()

                let request: HarnessInvokeRequest
                do {
                    request = try decoder.decode(HarnessInvokeRequest.self, from: lineData)
                } catch {
                    sendResponse(
                        HarnessInvokeResponse(
                            requestID: "",
                            status: .invalid,
                            summary: "Failed to decode harness request.",
                            errorCode: "invalid_json",
                            errorMessage: error.localizedDescription
                        ),
                        to: clientFileDescriptor
                    )
                    closeClient(clientFileDescriptor)
                    return
                }

                let requestHandler = requestHandler
                let callbackQueue = queue
                Task {
                    let response = await requestHandler(request)
                    callbackQueue.async { [weak self] in
                        guard let self else { return }
                        sendResponse(response, to: clientFileDescriptor)
                        closeClient(clientFileDescriptor)
                    }
                }
                return
            }

            if bytesRead == 0 {
                closeClient(clientFileDescriptor)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            closeClient(clientFileDescriptor)
            return
        }
    }

    private func sendResponse(_ response: HarnessInvokeResponse, to clientFileDescriptor: Int32) {
        guard let encoded = try? encoder.encode(response) else {
            return
        }

        var payload = encoded
        payload.append(0x0A)
        _ = payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return 0
            }
            return Darwin.write(clientFileDescriptor, baseAddress, rawBuffer.count)
        }
    }

    private func closeClient(_ clientFileDescriptor: Int32) {
        if let source = clientSources.removeValue(forKey: clientFileDescriptor) {
            source.cancel()
        }
        clientBuffers.removeValue(forKey: clientFileDescriptor)
        Darwin.close(clientFileDescriptor)
    }

    private static func systemErrorDescription() -> String {
        String(cString: strerror(errno))
    }
}
