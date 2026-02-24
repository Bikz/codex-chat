import AppKit
import Foundation
import SwiftTerm
import SwiftUI

struct ShellTerminalPaneView: NSViewRepresentable {
    let projectID: UUID
    let sessionID: UUID
    let pane: ShellPaneState
    let onTitleChanged: (UUID, UUID, UUID, String) -> Void
    let onCWDChanged: (UUID, UUID, UUID, String) -> Void
    let onProcessTerminated: (UUID, UUID, UUID, Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            projectID: projectID,
            sessionID: sessionID,
            paneID: pane.id,
            onTitleChanged: onTitleChanged,
            onCWDChanged: onCWDChanged,
            onProcessTerminated: onProcessTerminated
        )
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        Self.launchShell(on: view, cwd: pane.cwd)
        return view
    }

    func updateNSView(_: LocalProcessTerminalView, context: Context) {
        context.coordinator.projectID = projectID
        context.coordinator.sessionID = sessionID
        context.coordinator.paneID = pane.id
    }

    @MainActor
    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator _: Coordinator) {
        nsView.processDelegate = nil
        if nsView.process.running {
            nsView.terminate()
        }
    }

    nonisolated static func normalizeReportedDirectory(_ directory: String?) -> String? {
        guard let directory else { return nil }
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.isFileURL
        {
            let path = url.path
            return path.isEmpty ? nil : path
        }

        return trimmed
    }

    private static func launchShell(on view: LocalProcessTerminalView, cwd: String) {
        let shell = resolvedShellExecutable()
        view.startProcess(executable: shell, args: ["-l"], currentDirectory: cwd)
    }

    private static func resolvedShellExecutable() -> String {
        if let value = ProcessInfo.processInfo.environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }
        return "/bin/zsh"
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private final class StringUpdatePayload: NSObject {
            let projectID: UUID
            let sessionID: UUID
            let paneID: UUID
            let value: String

            init(projectID: UUID, sessionID: UUID, paneID: UUID, value: String) {
                self.projectID = projectID
                self.sessionID = sessionID
                self.paneID = paneID
                self.value = value
            }
        }

        private final class TerminationUpdatePayload: NSObject {
            let projectID: UUID
            let sessionID: UUID
            let paneID: UUID
            let exitCode: Int32?

            init(projectID: UUID, sessionID: UUID, paneID: UUID, exitCode: Int32?) {
                self.projectID = projectID
                self.sessionID = sessionID
                self.paneID = paneID
                self.exitCode = exitCode
            }
        }

        var projectID: UUID
        var sessionID: UUID
        var paneID: UUID

        private let onTitleChanged: (UUID, UUID, UUID, String) -> Void
        private let onCWDChanged: (UUID, UUID, UUID, String) -> Void
        private let onProcessTerminated: (UUID, UUID, UUID, Int32?) -> Void
        private var lastReportedTitle: String?
        private var lastReportedDirectory: String?
        private var hasReportedTermination = false
        private var lastReportedExitCode: Int32?

        init(
            projectID: UUID,
            sessionID: UUID,
            paneID: UUID,
            onTitleChanged: @escaping (UUID, UUID, UUID, String) -> Void,
            onCWDChanged: @escaping (UUID, UUID, UUID, String) -> Void,
            onProcessTerminated: @escaping (UUID, UUID, UUID, Int32?) -> Void
        ) {
            self.projectID = projectID
            self.sessionID = sessionID
            self.paneID = paneID
            self.onTitleChanged = onTitleChanged
            self.onCWDChanged = onCWDChanged
            self.onProcessTerminated = onProcessTerminated
        }

        func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {}

        func setTerminalTitle(source _: LocalProcessTerminalView, title: String) {
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            let payload = StringUpdatePayload(
                projectID: projectID,
                sessionID: sessionID,
                paneID: paneID,
                value: normalized
            )

            if Thread.isMainThread {
                applyTitleUpdate(payload)
            } else {
                performSelector(
                    onMainThread: #selector(applyTitleUpdateSelector(_:)),
                    with: payload,
                    waitUntilDone: false
                )
            }
        }

        func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            guard let path = ShellTerminalPaneView.normalizeReportedDirectory(directory) else {
                return
            }
            let payload = StringUpdatePayload(
                projectID: projectID,
                sessionID: sessionID,
                paneID: paneID,
                value: path
            )
            if Thread.isMainThread {
                applyDirectoryUpdate(payload)
            } else {
                performSelector(
                    onMainThread: #selector(applyDirectoryUpdateSelector(_:)),
                    with: payload,
                    waitUntilDone: false
                )
            }
        }

        func processTerminated(source _: TerminalView, exitCode: Int32?) {
            let payload = TerminationUpdatePayload(
                projectID: projectID,
                sessionID: sessionID,
                paneID: paneID,
                exitCode: exitCode
            )
            if Thread.isMainThread {
                applyTerminationUpdate(payload)
            } else {
                performSelector(
                    onMainThread: #selector(applyTerminationUpdate(_:)),
                    with: payload,
                    waitUntilDone: false
                )
            }
        }

        @objc
        private func applyTitleUpdateSelector(_ payload: StringUpdatePayload) {
            applyTitleUpdate(payload)
        }

        private func applyTitleUpdate(_ payload: StringUpdatePayload) {
            guard payload.projectID == projectID,
                  payload.sessionID == sessionID,
                  payload.paneID == paneID
            else {
                return
            }
            let title = payload.value
            guard lastReportedTitle != title else { return }
            lastReportedTitle = title
            onTitleChanged(projectID, sessionID, paneID, title)
        }

        @objc
        private func applyDirectoryUpdateSelector(_ payload: StringUpdatePayload) {
            applyDirectoryUpdate(payload)
        }

        private func applyDirectoryUpdate(_ payload: StringUpdatePayload) {
            guard payload.projectID == projectID,
                  payload.sessionID == sessionID,
                  payload.paneID == paneID
            else {
                return
            }
            let directory = payload.value
            guard lastReportedDirectory != directory else { return }
            lastReportedDirectory = directory
            onCWDChanged(projectID, sessionID, paneID, directory)
        }

        @objc
        private func applyTerminationUpdate(_ payload: TerminationUpdatePayload) {
            guard payload.projectID == projectID,
                  payload.sessionID == sessionID,
                  payload.paneID == paneID
            else {
                return
            }
            let decodedExitCode = payload.exitCode

            if hasReportedTermination, lastReportedExitCode == decodedExitCode {
                return
            }
            hasReportedTermination = true
            lastReportedExitCode = decodedExitCode
            onProcessTerminated(projectID, sessionID, paneID, decodedExitCode)
        }
    }
}
