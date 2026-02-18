import CodexChatCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            conversationCanvas
        }
        .onAppear {
            model.onAppear()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Button(action: model.createProject) {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            List(model.projects, selection: Binding(get: {
                model.selectedProjectID
            }, set: { selection in
                model.selectProject(selection)
            })) { project in
                Text(project.name)
                    .tag(project.id)
            }
            .frame(minHeight: 180)

            HStack {
                Text("Threads")
                    .font(.headline)
                Spacer()
                Button(action: model.createThread) {
                    Label("New Thread", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedProjectID == nil)
            }

            List(model.threads, selection: Binding(get: {
                model.selectedThreadID
            }, set: { selection in
                model.selectThread(selection)
            })) { thread in
                Text(thread.title)
                    .tag(thread.id)
            }

            Spacer()
        }
        .padding()
    }

    private var conversationCanvas: some View {
        VStack(spacing: 0) {
            if let error = model.bootError {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.selectedThreadID == nil {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Choose or create a thread to start chatting.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.messagesForSelectedThread()) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Ask CodexChat to do something…", text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button("Send") {
                    model.sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedThreadID == nil)
            }
            .padding()
        }
        .navigationTitle("Conversation")
    }
}
