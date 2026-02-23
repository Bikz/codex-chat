import CodexChatUI
import Foundation
import MarkdownUI
import SwiftUI

enum MarkdownSafetyPolicy: Equatable, Sendable {
    case trusted
    case untrusted

    var allowsExternalLinks: Bool {
        self == .trusted
    }

    var allowsExternalImages: Bool {
        self == .trusted
    }
}

enum MarkdownMessageSegment: Hashable {
    case markdown(String)
    case mermaid(String)
}

enum MarkdownMessageProcessor {
    private static let markdownImagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
    private static let markdownLinkPattern = #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#

    static func sanitize(_ input: String, policy: MarkdownSafetyPolicy) -> String {
        guard policy == .untrusted else {
            return input
        }

        return sanitizeOutsideCodeFences(input) { block in
            var sanitized = block
            sanitized = blockExternalImages(in: sanitized)
            sanitized = blockExternalLinks(in: sanitized)
            return sanitized
        }
    }

    static func parseSegments(_ input: String) -> [MarkdownMessageSegment] {
        let lines = input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var segments: [MarkdownMessageSegment] = []
        var markdownBuffer: [String] = []
        var mermaidBuffer: [String] = []
        var insideMermaid = false

        func flushMarkdown() {
            guard !markdownBuffer.isEmpty else { return }
            let block = markdownBuffer.joined(separator: "\n")
            if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdown(block))
            }
            markdownBuffer.removeAll(keepingCapacity: true)
        }

        func flushMermaid() {
            guard !mermaidBuffer.isEmpty else {
                segments.append(.mermaid(""))
                return
            }
            let block = mermaidBuffer.joined(separator: "\n")
            segments.append(.mermaid(block))
            mermaidBuffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if insideMermaid {
                if trimmed == "```" {
                    flushMermaid()
                    insideMermaid = false
                } else {
                    mermaidBuffer.append(line)
                }
                continue
            }

            if trimmed.lowercased() == "```mermaid" {
                flushMarkdown()
                insideMermaid = true
                continue
            }

            markdownBuffer.append(line)
        }

        if insideMermaid {
            markdownBuffer.append("```mermaid")
            markdownBuffer.append(contentsOf: mermaidBuffer)
            mermaidBuffer.removeAll(keepingCapacity: true)
        }

        flushMarkdown()

        if segments.isEmpty {
            return [.markdown(input)]
        }

        return segments
    }

    static func isExternalURL(_ url: URL?) -> Bool {
        guard let url else {
            return false
        }

        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private static func sanitizeOutsideCodeFences(
        _ input: String,
        transform: (String) -> String
    ) -> String {
        let lines = input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var outputLines: [String] = []
        var textBuffer: [String] = []
        var insideCodeFence = false

        func flushTextBuffer() {
            guard !textBuffer.isEmpty else { return }
            outputLines.append(transform(textBuffer.joined(separator: "\n")))
            textBuffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if insideCodeFence {
                    outputLines.append(line)
                    insideCodeFence = false
                } else {
                    flushTextBuffer()
                    outputLines.append(line)
                    insideCodeFence = true
                }
                continue
            }

            if insideCodeFence {
                outputLines.append(line)
            } else {
                textBuffer.append(line)
            }
        }

        flushTextBuffer()
        return outputLines.joined(separator: "\n")
    }

    private static func blockExternalImages(in input: String) -> String {
        replaceMatches(pattern: markdownImagePattern, in: input) { match, source in
            guard match.numberOfRanges >= 3,
                  let altRange = Range(match.range(at: 1), in: source),
                  let destinationRange = Range(match.range(at: 2), in: source)
            else {
                return nil
            }

            let alt = String(source[altRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = String(source[destinationRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isExternalURLString(destination) else {
                return nil
            }

            let label = alt.isEmpty ? "External image blocked in untrusted project." : "External image blocked in untrusted project: \(alt)."
            return "_\(label)_"
        }
    }

    private static func blockExternalLinks(in input: String) -> String {
        replaceMatches(pattern: markdownLinkPattern, in: input) { match, source in
            guard match.numberOfRanges >= 3,
                  let textRange = Range(match.range(at: 1), in: source),
                  let destinationRange = Range(match.range(at: 2), in: source)
            else {
                return nil
            }

            let label = String(source[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = String(source[destinationRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isExternalURLString(destination) else {
                return nil
            }

            if label.isEmpty {
                return "_External link blocked in untrusted project._"
            }

            return "\(label) _(external link blocked in untrusted project)_"
        }
    }

    private static func replaceMatches(
        pattern: String,
        in input: String,
        replacement: (NSTextCheckingResult, String) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return input
        }

        var output = input
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))

        for match in matches.reversed() {
            guard let range = Range(match.range, in: output),
                  let replacement = replacement(match, output)
            else {
                continue
            }
            output.replaceSubrange(range, with: replacement)
        }

        return output
    }

    private static func isExternalURLString(_ rawDestination: String) -> Bool {
        var destination = rawDestination
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

        if let token = destination.split(whereSeparator: { $0.isWhitespace }).first {
            destination = String(token)
        }

        guard let url = URL(string: destination) else {
            return false
        }

        return isExternalURL(url)
    }
}

struct MarkdownMessageView: View {
    @Environment(\.designTokens) private var tokens

    struct IndexedSegment: Identifiable, Hashable {
        let id: Int
        let segment: MarkdownMessageSegment
    }

    let text: String
    let allowsExternalContent: Bool
    private let safetyPolicy: MarkdownSafetyPolicy
    private let indexedSegments: [IndexedSegment]

    init(text: String, allowsExternalContent: Bool) {
        self.text = text
        self.allowsExternalContent = allowsExternalContent
        let policy: MarkdownSafetyPolicy = allowsExternalContent ? .trusted : .untrusted
        safetyPolicy = policy
        indexedSegments = Self.buildIndexedSegments(text: text, policy: policy)
    }

    nonisolated static func buildIndexedSegments(text: String, policy: MarkdownSafetyPolicy) -> [IndexedSegment] {
        let renderedText = MarkdownMessageProcessor.sanitize(text, policy: policy)
        let segments = MarkdownMessageProcessor.parseSegments(renderedText)
        return segments.enumerated().map { offset, segment in
            IndexedSegment(id: offset, segment: segment)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(indexedSegments) { indexedSegment in
                switch indexedSegment.segment {
                case let .markdown(markdown):
                    markdownText(markdown)
                case let .mermaid(source):
                    MermaidDiagramView(source: source)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownText(_ markdown: String) -> some View {
        Markdown(markdown)
            .markdownTheme(markdownTheme)
            .markdownImageProvider(PolicyImageProvider(policy: safetyPolicy))
            .environment(\.openURL, markdownOpenURLAction)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var markdownTheme: Theme {
        let accent = Color(hex: tokens.palette.accentHex)
        let line = Color.primary.opacity(tokens.surfaces.hairlineOpacity)
        let raised = Color.primary.opacity(tokens.surfaces.baseOpacity)

        return .gitHub
            .text {
                ForegroundColor(.primary)
                FontSize(Double(tokens.typography.bodySize))
            }
            .link {
                ForegroundColor(accent)
                FontWeight(.semibold)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.86))
                BackgroundColor(raised)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(line)
                            .frame(height: 1)
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
                    .padding(.bottom, 3)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(line.opacity(0.8))
                            .frame(height: 1)
                    }
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: tokens.radius.small)
                        .fill(accent.opacity(0.5))
                        .frame(width: 4)
                    configuration.label
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .background(raised, in: RoundedRectangle(cornerRadius: tokens.radius.small))
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.86))
                        }
                        .padding(12)
                }
                .background(raised, in: RoundedRectangle(cornerRadius: tokens.radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: tokens.radius.small)
                        .stroke(line)
                )
            }
            .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(color: line))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(Color.clear, raised.opacity(0.8))
                    )
            }
    }

    private var markdownOpenURLAction: OpenURLAction {
        OpenURLAction { url in
            if safetyPolicy.allowsExternalLinks || !MarkdownMessageProcessor.isExternalURL(url) {
                return .systemAction(url)
            }
            return .handled
        }
    }
}

private struct PolicyImageProvider: ImageProvider {
    let policy: MarkdownSafetyPolicy

    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if policy.allowsExternalImages || !MarkdownMessageProcessor.isExternalURL(url) {
            DefaultImageProvider.default.makeImage(url: url)
        } else {
            Label("External image blocked", systemImage: "photo.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
    }
}
