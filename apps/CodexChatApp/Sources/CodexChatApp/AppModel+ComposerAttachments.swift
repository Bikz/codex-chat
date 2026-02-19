import AppKit
import CodexKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func pickComposerAttachments() {
        guard selectedProjectID != nil else {
            followUpStatusMessage = "Select a project before attaching files."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.title = "Attach Files"
        panel.prompt = "Attach"

        guard panel.runModal() == .OK else {
            return
        }

        addComposerAttachments(panel.urls)
    }

    func addComposerAttachments(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        var existingPaths = Set(composerAttachments.map(\.path))
        var addedCount = 0

        for url in urls {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard !path.isEmpty,
                  existingPaths.insert(path).inserted
            else {
                continue
            }

            let attachment = ComposerAttachment(
                path: path,
                name: standardized.lastPathComponent,
                kind: composerAttachmentKind(for: standardized)
            )
            composerAttachments.append(attachment)
            addedCount += 1
        }

        if addedCount > 0 {
            followUpStatusMessage = "Attached \(addedCount) item\(addedCount == 1 ? "" : "s")."
        }
    }

    func removeComposerAttachment(_ attachmentID: UUID) {
        composerAttachments.removeAll { $0.id == attachmentID }
    }

    func clearComposerAttachments() {
        composerAttachments.removeAll()
    }

    func runtimeInputItemsForComposerAttachments(_ attachments: [ComposerAttachment]) -> [RuntimeInputItem] {
        attachments.map { attachment in
            switch attachment.kind {
            case .localImage:
                .localImage(path: attachment.path)
            case .mentionFile:
                .mention(name: attachment.name, path: attachment.path)
            }
        }
    }

    func displayTextForComposerSubmission(text: String, attachments: [ComposerAttachment]) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else {
            return trimmedText
        }

        let intro = trimmedText.isEmpty ? "Attached context." : trimmedText
        let lines = attachments.map { attachment in
            switch attachment.kind {
            case .localImage:
                "- [Image] \(attachment.name)"
            case .mentionFile:
                "- [File] \(attachment.name)"
            }
        }

        return "\(intro)\n\nAttachments:\n\(lines.joined(separator: "\n"))"
    }

    func runtimeTextForComposerSubmission(text: String, attachments: [ComposerAttachment]) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty, !attachments.isEmpty else {
            return trimmedText
        }
        return "Use the attached context to answer this request."
    }

    private func composerAttachmentKind(for url: URL) -> ComposerAttachmentKind {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           type.conforms(to: .image)
        {
            return .localImage
        }

        return .mentionFile
    }
}
