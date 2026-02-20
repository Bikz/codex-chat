import Darwin
import Foundation

private struct HarnessInvokeRequest: Codable {
    let protocolVersion: Int
    let requestID: String
    let sessionToken: String?
    let runToken: String
    let actionID: String
    let argumentsJson: String
}

private struct HarnessInvokeResponse: Codable {
    let requestID: String
    let status: String
    let summary: String
    let pendingApprovalID: String?
    let errorCode: String?
    let errorMessage: String?

    init(
        requestID: String,
        status: String,
        summary: String,
        pendingApprovalID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.requestID = requestID
        self.status = status
        self.summary = summary
        self.pendingApprovalID = pendingApprovalID
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

private struct ParsedInvokeCommand {
    let runToken: String
    let actionID: String
    let argumentsJSON: String
    let requestID: String
}

@main
struct CodexChatActionCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            emitAndExit(
                HarnessInvokeResponse(
                    requestID: "",
                    status: "invalid",
                    summary: "Missing command.",
                    errorCode: "missing_command",
                    errorMessage: "Use: codexchat-action invoke ..."
                ),
                code: EXIT_FAILURE
            )
        }

        switch command {
        case "invoke":
            runInvoke(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            emitAndExit(
                HarnessInvokeResponse(
                    requestID: "",
                    status: "invalid",
                    summary: "Unsupported command.",
                    errorCode: "unsupported_command",
                    errorMessage: "Use: codexchat-action invoke ..."
                ),
                code: EXIT_FAILURE
            )
        }
    }

    private static func runInvoke(arguments: [String]) {
        let parsed: ParsedInvokeCommand
        do {
            parsed = try parseInvoke(arguments: arguments)
        } catch let error as LocalizedError {
            emitAndExit(
                HarnessInvokeResponse(
                    requestID: "",
                    status: "invalid",
                    summary: "Invalid invoke arguments.",
                    errorCode: "invalid_arguments",
                    errorMessage: error.errorDescription
                ),
                code: EXIT_FAILURE
            )
        } catch {
            emitAndExit(
                HarnessInvokeResponse(
                    requestID: "",
                    status: "invalid",
                    summary: "Invalid invoke arguments.",
                    errorCode: "invalid_arguments",
                    errorMessage: error.localizedDescription
                ),
                code: EXIT_FAILURE
            )
        }

        let environment = ProcessInfo.processInfo.environment
        guard let socketPath = environment["CODEXCHAT_HARNESS_SOCKET"],
              !socketPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sessionToken = environment["CODEXCHAT_HARNESS_SESSION_TOKEN"],
              !sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            emitAndExit(
                HarnessInvokeResponse(
                    requestID: parsed.requestID,
                    status: "unauthorized",
                    summary: "Harness session is not configured.",
                    errorCode: "missing_harness_environment",
                    errorMessage: "Missing CODEXCHAT_HARNESS_SOCKET or CODEXCHAT_HARNESS_SESSION_TOKEN."
                ),
                code: EXIT_FAILURE
            )
        }

        let request = HarnessInvokeRequest(
            protocolVersion: 1,
            requestID: parsed.requestID,
            sessionToken: sessionToken,
            runToken: parsed.runToken,
            actionID: parsed.actionID,
            argumentsJson: parsed.argumentsJSON
        )

        do {
            let response = try invokeHarness(socketPath: socketPath, request: request)
            let exitCode: Int32 = switch response.status {
            case "executed", "queued_for_approval":
                EXIT_SUCCESS
            default:
                EXIT_FAILURE
            }
            emitAndExit(response, code: exitCode)
        } catch {
            emitAndExit(
                HarnessInvokeResponse(
                    requestID: parsed.requestID,
                    status: "invalid",
                    summary: "Failed to invoke harness endpoint.",
                    errorCode: "transport_error",
                    errorMessage: error.localizedDescription
                ),
                code: EXIT_FAILURE
            )
        }
    }

    private static func parseInvoke(arguments: [String]) throws -> ParsedInvokeCommand {
        enum ParseError: LocalizedError {
            case missingValue(String)
            case unknownOption(String)
            case missingRequired(String)
            case invalidArgumentsJSON(String)

            var errorDescription: String? {
                switch self {
                case let .missingValue(option):
                    "Missing value for \(option)."
                case let .unknownOption(option):
                    "Unknown option: \(option)."
                case let .missingRequired(option):
                    "Missing required option: \(option)."
                case let .invalidArgumentsJSON(detail):
                    "Invalid --arguments-json payload: \(detail)"
                }
            }
        }

        var runToken: String?
        var actionID: String?
        var argumentsJSON = "{}"
        var requestID: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--run-token":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(argument)
                }
                runToken = arguments[index + 1]
                index += 2

            case "--action-id":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(argument)
                }
                actionID = arguments[index + 1]
                index += 2

            case "--arguments-json":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(argument)
                }
                argumentsJSON = arguments[index + 1]
                index += 2

            case "--request-id":
                guard index + 1 < arguments.count else {
                    throw ParseError.missingValue(argument)
                }
                requestID = arguments[index + 1]
                index += 2

            default:
                throw ParseError.unknownOption(argument)
            }
        }

        guard let runToken, !runToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.missingRequired("--run-token")
        }
        guard let actionID, !actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.missingRequired("--action-id")
        }

        let canonicalArgumentsJSON: String
        do {
            let data = Data(argumentsJSON.utf8)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dictionary = object as? [String: Any] else {
                throw ParseError.invalidArgumentsJSON("payload must decode to a JSON object")
            }
            let canonicalData = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            canonicalArgumentsJSON = String(data: canonicalData, encoding: .utf8) ?? "{}"
        } catch let parseError as ParseError {
            throw parseError
        } catch {
            throw ParseError.invalidArgumentsJSON(error.localizedDescription)
        }

        return ParsedInvokeCommand(
            runToken: runToken,
            actionID: actionID,
            argumentsJSON: canonicalArgumentsJSON,
            requestID: requestID ?? UUID().uuidString.lowercased()
        )
    }

    private static func invokeHarness(
        socketPath: String,
        request: HarnessInvokeRequest
    ) throws -> HarnessInvokeResponse {
        let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw SocketError("Failed to create socket: \(String(cString: strerror(errno)))")
        }
        defer { Darwin.close(socketFD) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= sunPathCapacity else {
            throw SocketError("Socket path is too long.")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.initializeMemory(as: CChar.self, repeating: 0)
            for (index, value) in pathBytes.enumerated() where index < bytes.count {
                bytes[index] = UInt8(bitPattern: value)
            }
        }

        var addressCopy = address
        let addressLength = socklen_t(MemoryLayout.size(ofValue: addressCopy))
        let connectResult = withUnsafePointer(to: &addressCopy) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socketFD, sockaddrPointer, addressLength)
            }
        }

        guard connectResult == 0 else {
            throw SocketError("Failed to connect to harness socket: \(String(cString: strerror(errno)))")
        }

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        var payload = requestData
        payload.append(0x0A)
        let writeResult = payload.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else {
                return -1
            }
            return Darwin.write(socketFD, baseAddress, rawBuffer.count)
        }
        guard writeResult >= 0 else {
            throw SocketError("Failed to write harness request: \(String(cString: strerror(errno)))")
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            if count < 0 {
                throw SocketError("Failed to read harness response: \(String(cString: strerror(errno)))")
            }
            if count == 0 {
                break
            }

            responseData.append(buffer, count: count)
            if responseData.contains(0x0A) || responseData.count > 131_072 {
                break
            }
        }

        guard !responseData.isEmpty else {
            throw SocketError("Harness returned an empty response.")
        }

        if let newlineIndex = responseData.firstIndex(of: 0x0A) {
            responseData = responseData.prefix(upTo: newlineIndex)
        }

        return try JSONDecoder().decode(HarnessInvokeResponse.self, from: responseData)
    }

    private static func emitAndExit(_ response: HarnessInvokeResponse, code: Int32) -> Never {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(response),
           let text = String(data: data, encoding: .utf8)
        {
            print(text)
        } else {
            print(#"{"requestID":"","status":"invalid","summary":"Failed to encode response.","errorCode":"encoding_failed"}"#)
        }
        Foundation.exit(code)
    }

    private static func printUsage() {
        print(
            """
            Usage:
              codexchat-action invoke --run-token <token> --action-id <id> --arguments-json '{"key":"value"}' [--request-id <id>]
            """
        )
    }
}

private struct SocketError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
