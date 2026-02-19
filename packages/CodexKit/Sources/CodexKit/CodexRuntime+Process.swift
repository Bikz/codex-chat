import Foundation

extension CodexRuntime {
    func spawnProcess(executablePath: String) async throws {
        await correlator.resetTransport()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]
        process.environment = Self.mergedEnvironment(
            base: ProcessInfo.processInfo.environment,
            overrides: environmentOverrides
        )

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task {
                await self?.handleProcessTermination(status: status)
            }
        }

        try process.run()

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        framer = JSONLFramer()
        stderrLineBuffer = Data()

        installReadHandlers()
    }

    private func installReadHandlers() {
        guard let stdoutHandle, let stderrHandle else {
            return
        }

        stdoutPumpContinuation?.finish()
        stderrPumpContinuation?.finish()
        stdoutPumpTask?.cancel()
        stderrPumpTask?.cancel()

        var stdoutContinuation: AsyncStream<Data>.Continuation?
        let stdoutStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            stdoutContinuation = continuation
        }
        let resolvedStdoutContinuation = stdoutContinuation!
        stdoutPumpContinuation = resolvedStdoutContinuation
        stdoutPumpTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stdoutStream {
                await consumeStdout(chunk)
            }
        }

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                resolvedStdoutContinuation.finish()
                handle.readabilityHandler = nil
                return
            }
            resolvedStdoutContinuation.yield(data)
        }

        var stderrContinuation: AsyncStream<Data>.Continuation?
        let stderrStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            stderrContinuation = continuation
        }
        let resolvedStderrContinuation = stderrContinuation!
        stderrPumpContinuation = resolvedStderrContinuation
        stderrPumpTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stderrStream {
                await consumeStderr(chunk)
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                resolvedStderrContinuation.finish()
                handle.readabilityHandler = nil
                return
            }
            resolvedStderrContinuation.yield(data)
        }
    }

    private func consumeStdout(_ data: Data) async {
        if data.isEmpty {
            return
        }

        do {
            let frames = try framer.append(data)
            for frame in frames {
                let message = try decoder.decode(JSONRPCMessageEnvelope.self, from: frame)
                try await handleIncomingMessage(message)
            }
        } catch let error as JSONLFramerError {
            eventContinuation.yield(
                .action(
                    RuntimeAction(
                        method: "runtime/stdout/decode_error",
                        itemID: nil,
                        itemType: nil,
                        threadID: nil,
                        turnID: nil,
                        title: "Runtime stream framing error",
                        detail: error.localizedDescription
                    )
                )
            )

            // Buffer overflow means we can't safely resynchronize; stop and require restart.
            if case .bufferOverflow = error {
                await stopProcess()
            }
        } catch {
            eventContinuation.yield(
                .action(
                    RuntimeAction(
                        method: "runtime/stdout/decode_error",
                        itemID: nil,
                        itemType: nil,
                        threadID: nil,
                        turnID: nil,
                        title: "Runtime stream decode error",
                        detail: error.localizedDescription
                    )
                )
            )
        }
    }

    private func consumeStderr(_ data: Data) async {
        if data.isEmpty {
            return
        }

        stderrLineBuffer.append(data)
        while let newlineIndex = stderrLineBuffer.firstIndex(of: 0x0A) {
            let lineData = stderrLineBuffer.prefix(upTo: newlineIndex)
            stderrLineBuffer.removeSubrange(...newlineIndex)
            emitStderrLine(Data(lineData))
        }

        // If stderr is a stream without newlines, flush periodically to keep memory bounded.
        if stderrLineBuffer.count > 256 * 1024 {
            emitStderrLine(stderrLineBuffer)
            stderrLineBuffer = Data()
        }
    }

    func stopProcess() async {
        if !stderrLineBuffer.isEmpty {
            emitStderrLine(stderrLineBuffer)
            stderrLineBuffer = Data()
        }
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutPumpContinuation?.finish()
        stderrPumpContinuation?.finish()
        stdoutPumpTask?.cancel()
        stderrPumpTask?.cancel()
        stdoutPumpContinuation = nil
        stderrPumpContinuation = nil
        stdoutPumpTask = nil
        stderrPumpTask = nil

        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        stderrLineBuffer = Data()
        pendingApprovalRequests.removeAll()
        runtimeCapabilities = .none

        await correlator.failAll(error: CodexRuntimeError.transportClosed)
    }

    private func handleProcessTermination(status: Int32) async {
        if !stderrLineBuffer.isEmpty {
            emitStderrLine(stderrLineBuffer)
            stderrLineBuffer = Data()
        }
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutPumpContinuation?.finish()
        stderrPumpContinuation?.finish()
        stdoutPumpTask?.cancel()
        stderrPumpTask?.cancel()
        stdoutPumpContinuation = nil
        stderrPumpContinuation = nil
        stdoutPumpTask = nil
        stderrPumpTask = nil

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        stderrLineBuffer = Data()
        pendingApprovalRequests.removeAll()
        runtimeCapabilities = .none

        await correlator.failAll(error: CodexRuntimeError.transportClosed)

        let action = RuntimeAction(
            method: "runtime/terminated",
            itemID: nil,
            itemType: nil,
            threadID: nil,
            turnID: nil,
            title: "Runtime terminated",
            detail: "codex app-server exited with status \(status)."
        )
        eventContinuation.yield(.action(action))
    }

    private func emitStderrLine(_ lineData: Data) {
        let trimmed = String(bytes: lineData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let message = trimmed, !message.isEmpty else {
            return
        }

        eventContinuation.yield(
            .action(
                RuntimeAction(
                    method: "runtime/stderr",
                    itemID: nil,
                    itemType: nil,
                    threadID: nil,
                    turnID: nil,
                    title: "Runtime stderr",
                    detail: message
                )
            )
        )
    }
}
