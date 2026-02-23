@testable import CodexChatShared
import Darwin
import Foundation
import XCTest

final class ComputerActionHarnessServerTests: XCTestCase {
    func testServerRejectsInvalidJSONRequest() throws {
        let socketURL = try makeSocketURL()
        defer { try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent()) }

        let server = ComputerActionHarnessServer(socketPath: socketURL.path) { request in
            HarnessInvokeResponse(
                requestID: request.requestID,
                status: .executed,
                summary: "ok"
            )
        }
        try server.start()
        defer { server.stop() }

        let response = try Self.invokeRaw(socketPath: socketURL.path, payload: Data("not-json\n".utf8))
        XCTAssertEqual(response.status, .invalid)
        XCTAssertEqual(response.errorCode, "invalid_json")
    }

    func testServerRejectsOversizedRequestPayload() throws {
        let socketURL = try makeSocketURL()
        defer { try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent()) }

        let server = ComputerActionHarnessServer(socketPath: socketURL.path) { request in
            HarnessInvokeResponse(
                requestID: request.requestID,
                status: .executed,
                summary: "ok"
            )
        }
        try server.start()
        defer { server.stop() }

        let oversized = String(repeating: "a", count: (128 * 1024) + 1)
        let response = try Self.invokeRaw(socketPath: socketURL.path, payload: Data("\(oversized)\n".utf8))
        XCTAssertEqual(response.status, .invalid)
        XCTAssertEqual(response.errorCode, "request_too_large")
    }

    private func makeSocketURL() throws -> URL {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("cch-\(token)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("harness.sock", isDirectory: false)
    }

    private static func invokeRaw(socketPath: String, payload: Data) throws -> HarnessInvokeResponse {
        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw NSError(
                domain: "ComputerActionHarnessServerTests",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create socket."]
            )
        }
        defer { Darwin.close(fileDescriptor) }

        try connect(fileDescriptor: fileDescriptor, socketPath: socketPath)
        try writeAll(fileDescriptor: fileDescriptor, payload: payload)
        Darwin.shutdown(fileDescriptor, SHUT_WR)

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytes = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if bytes > 0 {
                responseData.append(buffer, count: bytes)
                continue
            }
            if bytes == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            throw NSError(
                domain: "ComputerActionHarnessServerTests",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to read harness response."]
            )
        }

        let responseLine = responseData.split(separator: 0x0A, maxSplits: 1, omittingEmptySubsequences: true).first ?? []
        guard !responseLine.isEmpty else {
            throw NSError(
                domain: "ComputerActionHarnessServerTests",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Harness response was empty."]
            )
        }

        return try JSONDecoder().decode(HarnessInvokeResponse.self, from: Data(responseLine))
    }

    private static func connect(fileDescriptor: Int32, socketPath: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= sunPathCapacity else {
            throw NSError(
                domain: "ComputerActionHarnessServerTests",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Socket path exceeds AF_UNIX limit."]
            )
        }

        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.initializeMemory(as: CChar.self, repeating: 0)
            for (index, value) in pathBytes.enumerated() where index < bytes.count {
                bytes[index] = UInt8(bitPattern: value)
            }
        }

        var attempts = 0
        let addressLength = socklen_t(MemoryLayout.size(ofValue: address))
        while true {
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.connect(fileDescriptor, sockaddrPointer, addressLength)
                }
            }
            if result == 0 {
                return
            }
            attempts += 1
            if attempts >= 20 || errno != ENOENT {
                throw NSError(
                    domain: "ComputerActionHarnessServerTests",
                    code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to connect to harness socket."]
                )
            }
            usleep(25000)
        }
    }

    private static func writeAll(fileDescriptor: Int32, payload: Data) throws {
        try payload.withUnsafeBytes { rawBuffer in
            var remaining = rawBuffer.count
            var pointer = rawBuffer.baseAddress

            while remaining > 0 {
                let written = Darwin.write(fileDescriptor, pointer, remaining)
                if written > 0 {
                    remaining -= written
                    pointer = pointer?.advanced(by: written)
                    continue
                }
                if errno == EINTR {
                    continue
                }
                throw NSError(
                    domain: "ComputerActionHarnessServerTests",
                    code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to write harness request payload."]
                )
            }
        }
    }
}
