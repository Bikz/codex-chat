import CodexChatUI
import SwiftUI

struct ChatSetupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: tokens.spacing.large) {
            header

            VStack(spacing: tokens.spacing.medium) {
                accountCard
                runtimeCard
                projectCard
            }
            .frame(maxWidth: 560)

            Spacer(minLength: 0)
        }
        .padding(tokens.spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: tokens.palette.accentHex))

            Text("Welcome to CodexChat")
                .font(.system(size: 28, weight: .semibold))

            Text("Sign in, pick a project folder, and start a local-first chat with reviewable actions.")
                .font(.system(size: tokens.typography.bodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var accountCard: some View {
        SetupCard(
            title: "Account",
            subtitle: model.isSignedInForRuntime ? model.accountSummaryText : "Sign in to use Codex runtime"
        ) {
            HStack {
                Button("Sign in with ChatGPT") {
                    model.signInWithChatGPT()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: tokens.palette.accentHex))
                .disabled(model.isAccountOperationInProgress || !canAttemptSignIn)

                Button("Use API Key…") {
                    model.presentAPIKeyPrompt()
                }
                .buttonStyle(.bordered)
                .disabled(model.isAccountOperationInProgress || !canAttemptSignIn)

                Spacer()
            }

            Text("ChatGPT sign-in opens your browser. API keys are stored in macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runtimeCard: some View {
        let statusText: String = {
            if case .installCodex? = model.runtimeIssue { return "Codex CLI not found" }
            if let issue = model.runtimeIssue { return issue.message }
            switch model.runtimeStatus {
            case .idle:
                return "Not started"
            case .starting:
                return "Connecting…"
            case .connected:
                return "Connected"
            case .error:
                return "Unavailable"
            }
        }()

        return SetupCard(title: "Codex Runtime", subtitle: statusText) {
            if model.runtimeStatus == .starting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting to the local runtime…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if case .installCodex? = model.runtimeIssue {
                HStack {
                    Link("Open Install Docs", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: tokens.palette.accentHex))

                    Button("Restart Runtime") {
                        model.restartRuntime()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                Text("After installation, press Restart Runtime to connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.runtimeStatus == .error || model.runtimeIssue != nil {
                HStack {
                    Button("Restart Runtime") {
                        model.restartRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: tokens.palette.accentHex))
                    Spacer()
                }
            } else if model.runtimeStatus == .connected, model.runtimeIssue == nil {
                SetupSuccessRow(text: "Runtime ready")
            }
        }
    }

    private var projectCard: some View {
        let projectTitle = model.selectedProject?.name ?? "Choose a project folder"
        let projectPath = model.selectedProject?.path

        return SetupCard(title: "Project Folder", subtitle: projectTitle) {
            if let projectPath {
                Text(projectPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Button(model.selectedProject == nil ? "Open Project Folder…" : "Change Folder…") {
                    model.openProjectFolder()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: tokens.palette.accentHex))

                Spacer()
            }

            Text("CodexChat stores readable files in your project: `chats/`, `memory/`, `mods/`, and `artifacts/`.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var canAttemptSignIn: Bool {
        if case .installCodex? = model.runtimeIssue {
            return false
        }
        return true
    }
}

private struct SetupCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.designTokens) private var tokens

    fileprivate init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.materials.panelMaterial.material, in: RoundedRectangle(cornerRadius: tokens.radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: tokens.radius.medium)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

private struct SetupSuccessRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
