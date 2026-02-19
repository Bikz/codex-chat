import CodexChatUI
import SwiftUI

struct CodexConfigSettingsSection: View {
    enum EditorTab: String, CaseIterable, Identifiable {
        case schema
        case raw

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .schema:
                "Schema Form"
            case .raw:
                "Raw TOML"
            }
        }
    }

    @ObservedObject var model: AppModel

    @State private var selectedTab: EditorTab = .schema
    @State private var draftRoot: CodexConfigValue = .object([:])
    @State private var rawDraft = ""
    @State private var rawParseError: String?
    @State private var isProgrammaticRawUpdate = false
    @State private var isSchemaDraftDirty = false
    @State private var hasHydratedDraft = false
    @State private var rawParseDebounceTask: Task<Void, Never>?
    @Environment(\.designTokens) private var tokens

    private let rawParseDebounceNanoseconds: UInt64 = 220_000_000

    var body: some View {
        SettingsSectionCard(
            title: "Codex Config",
            subtitle: "User-level config from `config.toml` is the source of truth for defaults and flags."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.codexConfigSchemaSource.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tokens.materials.panelMaterial.material, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.14))
                        )
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            do {
                                try await model.loadCodexConfig()
                                await model.reloadCodexConfigSchema()
                                hydrateDraftFromModel()
                                model.codexConfigStatusMessage = "Reloaded config.toml from disk."
                            } catch {
                                model.codexConfigStatusMessage = "Failed to reload config.toml: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Button("Discard Draft") {
                        hydrateDraftFromModel()
                        model.codexConfigStatusMessage = "Discarded unsaved config changes."
                    }

                    Spacer(minLength: 0)

                    Button {
                        let hasBlockingRawError = selectedTab == .raw && rawParseError != nil
                        guard !hasBlockingRawError else {
                            model.codexConfigStatusMessage = "Fix TOML parse errors before saving."
                            return
                        }

                        var document = model.codexConfigDocument
                        document.root = draftRoot
                        model.replaceCodexConfigDocument(document)

                        Task {
                            await model.saveCodexConfigAndRestartRuntime()
                        }
                    } label: {
                        Label("Save + Restart Runtime", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isCodexConfigBusy || (selectedTab == .raw && rawParseError != nil))
                }

                Picker("Editor", selection: $selectedTab) {
                    ForEach(EditorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .schema {
                    ScrollView {
                        CodexConfigSchemaFormView(rootValue: $draftRoot, schema: model.codexConfigSchema)
                    }
                    .frame(minHeight: 360)
                } else {
                    CodexConfigRawEditorView(rawText: $rawDraft, parseError: rawParseError)
                        .onChange(of: rawDraft) { _, _ in
                            scheduleRawDraftParsing()
                        }
                }

                if !model.codexConfigValidationIssues.isEmpty {
                    Divider()
                    Text("Validation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(model.codexConfigValidationIssues) { issue in
                        Text("[\(issue.severity.rawValue.uppercased())] \(issue.pathLabel): \(issue.message)")
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .secondary)
                    }
                }

                if let status = model.codexConfigStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            guard !hasHydratedDraft else {
                return
            }
            hydrateDraftFromModel()
            hasHydratedDraft = true
        }
        .onChange(of: model.codexConfigDocument) { _, _ in
            hydrateDraftFromModel()
            hasHydratedDraft = true
        }
        .onChange(of: draftRoot) { _, _ in
            if selectedTab == .schema {
                isSchemaDraftDirty = true
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .raw, isSchemaDraftDirty else {
                return
            }
            syncRawFromDraftRoot()
            isSchemaDraftDirty = false
        }
        .onDisappear {
            rawParseDebounceTask?.cancel()
        }
    }

    private func hydrateDraftFromModel() {
        draftRoot = model.codexConfigDocument.root

        var document = model.codexConfigDocument
        if document.rawText.isEmpty {
            try? document.syncRawFromRoot()
        }

        isProgrammaticRawUpdate = true
        rawDraft = document.rawText
        isProgrammaticRawUpdate = false
        rawParseError = nil
        isSchemaDraftDirty = false
    }

    private func syncRawFromDraftRoot() {
        var document = model.codexConfigDocument
        document.root = draftRoot

        do {
            try document.syncRawFromRoot()
            isProgrammaticRawUpdate = true
            rawDraft = document.rawText
            isProgrammaticRawUpdate = false
            rawParseError = nil
        } catch {
            rawParseError = error.localizedDescription
        }
    }

    private func parseRawDraftIfNeeded() {
        guard !isProgrammaticRawUpdate else {
            return
        }

        do {
            let document = try model.parseCodexConfigRaw(rawDraft)
            draftRoot = document.root
            rawParseError = nil
        } catch {
            rawParseError = error.localizedDescription
        }
    }

    private func scheduleRawDraftParsing() {
        guard !isProgrammaticRawUpdate else {
            return
        }

        rawParseDebounceTask?.cancel()
        let draftAtScheduleTime = rawDraft
        rawParseDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: rawParseDebounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled, draftAtScheduleTime == rawDraft else {
                return
            }

            parseRawDraftIfNeeded()
        }
    }
}
