import AppKit
import CodexChatCore
import CodexChatUI
import CodexMemory
import SwiftUI

@MainActor
struct MemoryCanvas: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    @State private var writeMode: ProjectMemoryWriteMode = .off
    @State private var embeddingsEnabled = false
    @State private var isSyncingSettings = false

    @State private var selectedFileKind: MemoryFileKind = .profile
    @State private var pendingFileKind: MemoryFileKind?
    @State private var isUnsavedAlertVisible = false

    @State private var fileState: AppModel.SurfaceState<String> = .idle
    @State private var draftText = ""
    @State private var lastSavedText = ""
    @State private var isSaving = false

    @State private var isForgetConfirmationVisible = false
    @State private var isWipeIndexConfirmationVisible = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let project = model.selectedProject {
                content(project: project)
            } else {
                EmptyStateView(
                    title: "Select a project",
                    message: "Memory is stored per project in `memory/*.md`.",
                    systemImage: "brain"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Memory")
        .onAppear {
            syncSettingsFromSelectedProject()
        }
        .onChange(of: model.selectedProject?.id) { _ in
            syncSettingsFromSelectedProject()
        }
        .alert("Unsaved changes", isPresented: $isUnsavedAlertVisible) {
            Button("Save") {
                Task { await saveDraftAndSwitchIfNeeded() }
            }
            Button("Discard", role: .destructive) {
                discardDraftAndSwitchIfNeeded()
            }
            Button("Cancel", role: .cancel) {
                pendingFileKind = nil
            }
        } message: {
            Text("Save changes to \(selectedFileKind.fileName) before switching?")
        }
        .alert("Forget memory files?", isPresented: $isForgetConfirmationVisible) {
            Button("Forget", role: .destructive) {
                Task { await forgetMemory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes `memory/*.md` for the selected project. This cannot be undone.")
        }
        .alert("Wipe semantic index?", isPresented: $isWipeIndexConfirmationVisible) {
            Button("Wipe", role: .destructive) {
                Task { await wipeSemanticIndex() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the local semantic index file. It can be rebuilt later.")
        }
    }

    private var header: some View {
        HStack {
            Text("Memory")
                .font(.system(size: tokens.typography.titleSize, weight: .semibold))
            Spacer()

            Button("Reveal Folder") {
                Task { await revealMemoryFolder() }
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedProject == nil)

            Menu {
                Button("Forget Memory Files…", role: .destructive) {
                    isForgetConfirmationVisible = true
                }
                Button("Wipe Semantic Index…", role: .destructive) {
                    isWipeIndexConfirmationVisible = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .disabled(model.selectedProject == nil)
        }
        .padding(tokens.spacing.medium)
    }

    private func content(project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            settingsSection(project: project)

            Picker("Memory file", selection: fileKindSelectionBinding) {
                ForEach(MemoryFileKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            editorSurface(project: project)

            footerControls(project: project)

            Spacer(minLength: 0)
        }
        .padding(tokens.spacing.medium)
        .task(id: project.id) {
            await loadFile(for: project, kind: selectedFileKind)
        }
        .task(id: selectedFileKind) {
            await loadFile(for: project, kind: selectedFileKind)
        }
    }

    private func settingsSection(project _: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto-Write")
                .font(.headline)

            Picker("After each completed turn", selection: $writeMode) {
                Text("Off").tag(ProjectMemoryWriteMode.off)
                Text("Summaries only").tag(ProjectMemoryWriteMode.summariesOnly)
                Text("Summaries + key facts").tag(ProjectMemoryWriteMode.summariesAndKeyFacts)
            }
            .pickerStyle(.menu)
            .onChange(of: writeMode) { newValue in
                guard !isSyncingSettings else { return }
                model.updateSelectedProjectMemorySettings(writeMode: newValue, embeddingsEnabled: embeddingsEnabled)
            }

            Toggle("Enable semantic retrieval (advanced)", isOn: $embeddingsEnabled)
                .onChange(of: embeddingsEnabled) { newValue in
                    guard !isSyncingSettings else { return }
                    model.updateSelectedProjectMemorySettings(writeMode: writeMode, embeddingsEnabled: newValue)
                }

            Text("Memory files are stored inside the project folder under `memory/`. Auto-write is off by default for privacy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: tokens.radius.medium))
    }

    @ViewBuilder
    private func editorSurface(project: ProjectRecord) -> some View {
        switch fileState {
        case .idle, .loading:
            LoadingStateView(title: "Loading \(selectedFileKind.displayName)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ErrorStateView(title: "Memory unavailable", message: message, actionLabel: "Retry") {
                Task { await loadFile(for: project, kind: selectedFileKind) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            TextEditor(text: $draftText)
                .font(.system(.body, design: .monospaced))
                .overlay(
                    RoundedRectangle(cornerRadius: tokens.radius.medium)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .onChange(of: draftText) { _ in
                    // Update dirty state via lastSavedText.
                }
        }
    }

    private func footerControls(project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Reload") {
                    Task { await loadFile(for: project, kind: selectedFileKind) }
                }
                .buttonStyle(.bordered)

                Button(isSaving ? "Saving…" : "Save") {
                    Task { await saveDraft(for: project, kind: selectedFileKind) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty || isSaving)

                Button("Reveal File") {
                    Task { await revealSelectedFile(project: project, kind: selectedFileKind) }
                }
                .buttonStyle(.bordered)

                Spacer()

                if isDirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = model.memoryStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isDirty: Bool {
        draftText != lastSavedText
    }

    private var fileKindSelectionBinding: Binding<MemoryFileKind> {
        Binding(
            get: { selectedFileKind },
            set: { next in
                guard next != selectedFileKind else { return }
                if isDirty {
                    pendingFileKind = next
                    isUnsavedAlertVisible = true
                } else {
                    selectedFileKind = next
                }
            }
        )
    }

    private func syncSettingsFromSelectedProject() {
        guard let project = model.selectedProject else { return }
        isSyncingSettings = true
        writeMode = project.memoryWriteMode
        embeddingsEnabled = project.memoryEmbeddingsEnabled
        isSyncingSettings = false
    }

    private func loadFile(for project: ProjectRecord, kind: MemoryFileKind) async {
        fileState = .loading
        let store = ProjectMemoryStore(projectPath: project.path)

        do {
            try await store.ensureStructure()
            let text = try await store.read(kind)
            await MainActor.run {
                lastSavedText = text
                draftText = text
                fileState = .loaded(text)
            }
        } catch {
            await MainActor.run {
                fileState = .failed(error.localizedDescription)
            }
        }
    }

    private func saveDraft(for project: ProjectRecord, kind: MemoryFileKind) async {
        isSaving = true
        defer { isSaving = false }

        let store = ProjectMemoryStore(projectPath: project.path)
        do {
            try await store.write(kind, text: draftText)
            await MainActor.run {
                lastSavedText = draftText
                model.memoryStatusMessage = "Saved \(kind.fileName)."
            }
        } catch {
            await MainActor.run {
                model.memoryStatusMessage = "Failed to save memory file: \(error.localizedDescription)"
            }
        }
    }

    private func saveDraftAndSwitchIfNeeded() async {
        guard let project = model.selectedProject else { return }
        let next = pendingFileKind
        pendingFileKind = nil

        await saveDraft(for: project, kind: selectedFileKind)
        if !isDirty, let next {
            selectedFileKind = next
        }
    }

    private func discardDraftAndSwitchIfNeeded() {
        draftText = lastSavedText
        if let next = pendingFileKind {
            pendingFileKind = nil
            selectedFileKind = next
        }
    }

    private func revealMemoryFolder() async {
        guard let project = model.selectedProject else { return }
        let store = ProjectMemoryStore(projectPath: project.path)
        do {
            try await store.ensureStructure()
            let url = URL(fileURLWithPath: store.memoryDirectoryPath, isDirectory: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            await MainActor.run {
                model.memoryStatusMessage = "Revealed memory folder in Finder."
            }
        } catch {
            await MainActor.run {
                model.memoryStatusMessage = "Failed to reveal memory folder: \(error.localizedDescription)"
            }
        }
    }

    private func revealSelectedFile(project: ProjectRecord, kind: MemoryFileKind) async {
        let store = ProjectMemoryStore(projectPath: project.path)
        do {
            let path = try await store.filePath(for: kind)
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            await MainActor.run {
                model.memoryStatusMessage = "Revealed \(kind.fileName) in Finder."
            }
        } catch {
            await MainActor.run {
                model.memoryStatusMessage = "Failed to reveal memory file: \(error.localizedDescription)"
            }
        }
    }

    private func forgetMemory() async {
        guard let project = model.selectedProject else { return }
        let store = ProjectMemoryStore(projectPath: project.path)
        do {
            try await store.deleteAllMemoryFiles()
            await MainActor.run {
                fileState = .idle
                draftText = ""
                lastSavedText = ""
                model.memoryStatusMessage = "Forgot memory files for this project."
            }
        } catch {
            await MainActor.run {
                model.memoryStatusMessage = "Failed to forget memory: \(error.localizedDescription)"
            }
        }
    }

    private func wipeSemanticIndex() async {
        guard let project = model.selectedProject else { return }
        let store = ProjectMemoryStore(projectPath: project.path)
        do {
            try await store.wipeSemanticIndex()
            await MainActor.run {
                model.memoryStatusMessage = "Wiped semantic index."
            }
        } catch {
            await MainActor.run {
                model.memoryStatusMessage = "Failed to wipe index: \(error.localizedDescription)"
            }
        }
    }
}
