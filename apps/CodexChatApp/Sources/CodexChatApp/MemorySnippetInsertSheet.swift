import CodexChatCore
import CodexChatUI
import CodexMemory
import SwiftUI

@MainActor
struct MemorySnippetInsertSheet: View {
    enum SearchMode: String, CaseIterable {
        case keyword
        case semantic
    }

    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @Environment(\.designTokens) private var tokens

    @State private var query = ""
    @State private var mode: SearchMode = .keyword
    @State private var resultsState: AppModel.SurfaceState<[MemorySearchHit]> = .idle
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            HStack {
                Text("Insert Memory Snippet")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Open Memory") {
                    model.navigationSection = .memory
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }

            if let project = model.selectedProject {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search memory files", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _ in
                            scheduleSearch(project: project)
                        }

                    Picker("Mode", selection: $mode) {
                        Text("Keyword").tag(SearchMode.keyword)
                        if project.memoryEmbeddingsEnabled {
                            Text("Semantic").tag(SearchMode.semantic)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in
                        scheduleSearch(project: project)
                    }

                    resultsSurface(project: project)
                }
            } else {
                EmptyStateView(
                    title: "No project selected",
                    message: "Select a project to search memory.",
                    systemImage: "brain"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 520)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private func resultsSurface(project: ProjectRecord) -> some View {
        switch resultsState {
        case .idle:
            EmptyStateView(
                title: "Search memory",
                message: "Type to find a snippet to insert into your message.",
                systemImage: "magnifyingglass"
            )
        case .loading:
            LoadingStateView(title: "Searching memory…")
        case let .failed(message):
            ErrorStateView(title: "Search failed", message: message, actionLabel: "Retry") {
                scheduleSearch(project: project)
            }
        case let .loaded(hits) where hits.isEmpty:
            EmptyStateView(
                title: "No matches",
                message: "Try a different keyword.",
                systemImage: "doc.text.magnifyingglass"
            )
        case let .loaded(hits):
            List(hits) { hit in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.fileKind.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(hit.excerpt)
                            .font(.callout)
                            .lineLimit(3)
                    }
                    Spacer()
                    Button("Insert") {
                        insert(hit: hit)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))
        }
    }

    private func scheduleSearch(project: ProjectRecord) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resultsState = .idle
            return
        }

        resultsState = .loading
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 140_000_000)
                if Task.isCancelled { return }

                let store = ProjectMemoryStore(projectPath: project.path)
                let hits: [MemorySearchHit] = switch mode {
                case .keyword:
                    try await store.keywordSearch(query: trimmed, limit: 30)
                case .semantic:
                    try await store.semanticSearch(query: trimmed, limit: 20)
                }

                if Task.isCancelled { return }
                await MainActor.run {
                    resultsState = .loaded(hits)
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    resultsState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func insert(hit: MemorySearchHit) {
        let header = "Memory (\(hit.fileKind.displayName)):"
        let snippet = "\(header)\n\(hit.excerpt)"
        let existing = model.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        model.composerText = existing.isEmpty ? snippet : "\(existing)\n\n\(snippet)"
    }
}
