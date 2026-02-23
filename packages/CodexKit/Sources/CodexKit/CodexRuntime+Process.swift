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
        guard stdoutHandle != nil, stderrHandle != nil else {
            return
        }

        stdoutPumpContinuation?.finish()
        stderrPumpContinuation?.finish()
        stdoutPumpTask?.cancel()
        stderrPumpTask?.cancel()
        stdoutBufferedBytes = 0
        stderrBufferedBytes = 0
        isStdoutReadPaused = false
        isStderrReadPaused = false

        var stdoutContinuation: AsyncStream<Data>.Continuation?
        let stdoutStream = AsyncStream<Data>(bufferingPolicy: .unbounded) { continuation in
            stdoutContinuation = continuation
        }
        let resolvedStdoutContinuation = stdoutContinuation!
        stdoutPumpContinuation = resolvedStdoutContinuation
        stdoutPumpTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stdoutStream {
                await consumeStdout(chunk)
                await didConsumeStdoutChunk(byteCount: chunk.count)
            }
        }

        installStdoutReadabilityHandler(using: resolvedStdoutContinuation)

        var stderrContinuation: AsyncStream<Data>.Continuation?
        let stderrStream = AsyncStream<Data>(bufferingPolicy: .unbounded) { continuation in
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

        installStderrReadabilityHandler(using: resolvedStderrContinuation)
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
        stdoutBufferedBytes = 0
        stderrBufferedBytes = 0
        isStdoutReadPaused = false
        isStderrReadPaused = false
        pendingApprovalRequests.removeAll()
        nextLocalApprovalRequestID = 1
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
        stdoutBufferedBytes = 0
        stderrBufferedBytes = 0
        isStdoutReadPaused = false
        isStderrReadPaused = false
        pendingApprovalRequests.removeAll()
        nextLocalApprovalRequestID = 1
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

    private func installStdoutReadabilityHandler(using continuation: AsyncStream<Data>.Continuation) {
        guard let stdoutHandle else {
            return
        }

        isStdoutReadPaused = false
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.handleStdoutReadableData(data, continuation: continuation)
            }
        }
    }

    private func installStderrReadabilityHandler(using continuation: AsyncStream<Data>.Continuation) {
        guard let stderrHandle else {
            return
        }

        isStderrReadPaused = false
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                continuation.finish()
                handle.readabilityHandler = nil
                return
            }

            continuation.yield(data)
        }
    }

    private func handleStdoutReadableData(
        _ data: Data,
        continuation: AsyncStream<Data>.Continuation
    ) {
        guard !data.isEmpty else {
            continuation.finish()
            stdoutHandle?.readabilityHandler = nil
            isStdoutReadPaused = false
            stdoutBufferedBytes = 0
            return
        }

        switch continuation.yield(data) {
        case .enqueued:
            stdoutBufferedBytes += data.count
            if !isStdoutReadPaused,
               stdoutBufferedBytes >= Self.ioBackpressurePauseHighWatermarkBytes
            {
                stdoutHandle?.readabilityHandler = nil
                isStdoutReadPaused = true
            }
        case .dropped:
            // We use an unbounded stream and expect no drops.
            break
        case .terminated:
            break
        @unknown default:
            break
        }
    }

    private func didConsumeStdoutChunk(byteCount: Int) {
        stdoutBufferedBytes = max(0, stdoutBufferedBytes - byteCount)
        guard isStdoutReadPaused,
              stdoutBufferedBytes <= Self.ioBackpressureResumeLowWatermarkBytes,
              let continuation = stdoutPumpContinuation
        else {
            return
        }

        installStdoutReadabilityHandler(using: continuation)
    }
}
