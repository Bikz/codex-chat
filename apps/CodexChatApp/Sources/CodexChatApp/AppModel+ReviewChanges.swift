import CodexKit
import Foundation

extension AppModel {
    func toggleLogsDrawer() {
        isLogsDrawerVisible.toggle()
    }

    func openReviewChanges() {
        guard canReviewChanges else { return }
        isReviewChangesVisible = true
    }

    func closeReviewChanges() {
        isReviewChangesVisible = false
    }

    func acceptReviewChanges() {
        guard let selectedThreadID else { return }
        reviewChangesByThreadID[selectedThreadID] = []
        isReviewChangesVisible = false
        projectStatusMessage = "Accepted reviewed changes for this thread."
    }

    func revertReviewChanges() {
        guard let project = selectedProject else { return }
        let paths = Array(Set(selectedThreadChanges.map(\.path))).sorted()

        guard !paths.isEmpty else {
            projectStatusMessage = "No file paths available to revert."
            return
        }

        guard Self.isGitProject(path: project.path) else {
            projectStatusMessage = "Revert is available for Git projects only."
            return
        }

        do {
            try restorePathsWithGit(paths, projectPath: project.path)
            if let selectedThreadID {
                reviewChangesByThreadID[selectedThreadID] = []
            }
            isReviewChangesVisible = false
            projectStatusMessage = "Reverted \(paths.count) file(s) with git restore."
        } catch {
            projectStatusMessage = "Failed to revert files: \(error.localizedDescription)"
            appendLog(.error, "Revert failed: \(error.localizedDescription)")
        }
    }

    private func restorePathsWithGit(_ paths: [String], projectPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", projectPath, "restore", "--"] + paths

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(bytes: errorData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "CodexChatApp.GitRestore",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }
}
