import SwiftUI

public struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let systemImage: String
    private let actionLabel: String?
    private let action: (() -> Void)?
    private let shortcutHint: String?

    public init(
        title: String,
        message: String,
        systemImage: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil,
        shortcutHint: String? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionLabel = actionLabel
        self.action = action
        self.shortcutHint = shortcutHint
    }

    @Environment(\.designTokens) private var tokens

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: tokens.palette.accentHex).opacity(0.6))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
            }

            if let shortcutHint,
               !shortcutHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(shortcutHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

public struct LoadingStateView: View {
    private let title: String

    public init(title: String) {
        self.title = title
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    public var body: some View {
        VStack(spacing: 12) {
            ActivityIndicatorGlyph(size: .regular)
            Text(title)
                .foregroundStyle(.secondary)
                .opacity(Self.pulsingOpacity(isPulsing: isPulsing, reduceMotion: reduceMotion))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear {
                    isPulsing = !reduceMotion
                }
                .onChange(of: reduceMotion) { newValue in
                    isPulsing = !newValue
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    nonisolated static func pulsingOpacity(isPulsing: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1.0 }
        return isPulsing ? 0.5 : 1.0
    }
}

public struct ErrorStateView: View {
    private let title: String
    private let message: String
    private let actionLabel: String?
    private let action: (() -> Void)?

    public init(title: String, message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
            }
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
