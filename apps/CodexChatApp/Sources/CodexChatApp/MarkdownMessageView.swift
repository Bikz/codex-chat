import CodexChatUI
import Foundation
import MarkdownUI
import SwiftUI
#if canImport(AppKit)
    import AppKit
#endif

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
    struct FileReference: Hashable, Sendable {
        let path: String
        let line: Int?
        let column: Int?
    }

    private static let markdownImagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
    private static let markdownLinkPattern = #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#
    private static let backtickTokenPattern = #"`([^`\n]+)`"#

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

    static func linkifyProjectFileReferences(_ input: String) -> String {
        sanitizeOutsideCodeFences(input) { block in
            replaceMatches(pattern: backtickTokenPattern, in: block) { match, source in
                guard match.numberOfRanges >= 2,
                      let matchRange = Range(match.range, in: source),
                      let tokenRange = Range(match.range(at: 1), in: source)
                else {
                    return nil
                }

                // Skip existing markdown link labels like [`file`](dest).
                if isWrappedAsMarkdownLinkLabel(source: source, matchRange: matchRange) {
                    return nil
                }

                let token = String(source[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let reference = parseFileReference(token) else {
                    return nil
                }

                guard let link = projectFileURLString(reference: reference) else {
                    return nil
                }

                return "[`\(token)`](\(link))"
            }
        }
    }

    static func resolveProjectFileURL(_ url: URL, projectPath: String?) -> URL? {
        if url.scheme?.lowercased() == "codexchat-file",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        {
            let line = components.queryItems?
                .first(where: { $0.name == "line" })?
                .value
                .flatMap(Int.init)
            let column = components.queryItems?
                .first(where: { $0.name == "column" })?
                .value
                .flatMap(Int.init)
            let reference = FileReference(path: path, line: line, column: column)
            return resolveAbsoluteURL(for: reference, projectPath: projectPath)
        }

        if url.isFileURL {
            return url
        }

        guard url.scheme == nil else {
            return nil
        }

        let raw = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        guard let reference = parseFileReference(raw) else {
            return nil
        }
        return resolveAbsoluteURL(for: reference, projectPath: projectPath)
    }

    static func parseFileReference(_ raw: String) -> FileReference? {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !token.isEmpty, !token.contains(" ") else {
            return nil
        }

        var line: Int?
        var column: Int?

        if let anchorMatch = firstMatch(
            pattern: #"^(.*)#L(\d+)(?:C(\d+))?$"#,
            in: token
        ) {
            token = anchorMatch[0]
            line = Int(anchorMatch[1])
            if anchorMatch.count > 2 {
                column = Int(anchorMatch[2])
            }
        } else if let lineMatch = firstMatch(
            pattern: #"^(.*?):(\d+)(?::(\d+))?$"#,
            in: token
        ) {
            token = lineMatch[0]
            line = Int(lineMatch[1])
            if lineMatch.count > 2 {
                column = Int(lineMatch[2])
            }
        }

        let normalized = normalizePathToken(token)
        guard looksLikeFilePath(normalized) else {
            return nil
        }

        return FileReference(path: normalized, line: line, column: column)
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

    private static func projectFileURLString(reference: FileReference) -> String? {
        var components = URLComponents()
        components.scheme = "codexchat-file"
        components.host = "open"

        var queryItems = [URLQueryItem(name: "path", value: reference.path)]
        if let line = reference.line {
            queryItems.append(URLQueryItem(name: "line", value: String(line)))
        }
        if let column = reference.column {
            queryItems.append(URLQueryItem(name: "column", value: String(column)))
        }
        components.queryItems = queryItems

        return components.url?.absoluteString
    }

    private static func resolveAbsoluteURL(for reference: FileReference, projectPath: String?) -> URL? {
        let path = reference.path
        if path.hasPrefix("/") {
            let absolute = URL(fileURLWithPath: path).standardizedFileURL
            if let projectPath, !isPath(absolute.path, within: projectPath) {
                return nil
            }
            return absolute
        }

        guard let projectPath else {
            return nil
        }

        return ProjectPathSafety.destinationURL(for: path, projectPath: projectPath)
    }

    private static func isPath(_ path: String, within projectPath: String) -> Bool {
        let rootURL = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let candidateURL = URL(fileURLWithPath: path).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        return candidateURL.path.hasPrefix(rootPrefix)
    }

    private static func normalizePathToken(_ token: String) -> String {
        if token.hasPrefix("a/") || token.hasPrefix("b/") {
            return String(token.dropFirst(2))
        }
        return token
    }

    private static func looksLikeFilePath(_ token: String) -> Bool {
        if token.hasPrefix("/") {
            return true
        }
        if token.hasPrefix("./") || token.hasPrefix("../") {
            return true
        }
        if token.contains("/") {
            return true
        }
        let fileLikePattern = #"^[A-Za-z0-9._-]+\.[A-Za-z0-9]+$"#
        return token.range(of: fileLikePattern, options: .regularExpression) != nil
    }

    private static func firstMatch(pattern: String, in source: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1
        else {
            return nil
        }

        var captures: [String] = []
        captures.reserveCapacity(match.numberOfRanges - 1)
        for captureIndex in 1 ..< match.numberOfRanges {
            let captureRange = match.range(at: captureIndex)
            if captureRange.location == NSNotFound {
                captures.append("")
                continue
            }
            if let range = Range(captureRange, in: source) {
                captures.append(String(source[range]))
            } else {
                captures.append("")
            }
        }
        return captures
    }

    private static func isWrappedAsMarkdownLinkLabel(
        source: String,
        matchRange: Range<String.Index>
    ) -> Bool {
        guard matchRange.lowerBound > source.startIndex else {
            return false
        }
        let previous = source[source.index(before: matchRange.lowerBound)]
        guard previous == "[" else {
            return false
        }
        return source[matchRange.upperBound...].hasPrefix("](")
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
    private let projectPath: String?
    private let safetyPolicy: MarkdownSafetyPolicy
    private let indexedSegments: [IndexedSegment]

    init(
        text: String,
        allowsExternalContent: Bool,
        projectPath: String? = nil
    ) {
        self.text = text
        self.allowsExternalContent = allowsExternalContent
        self.projectPath = projectPath
        let policy: MarkdownSafetyPolicy = allowsExternalContent ? .trusted : .untrusted
        safetyPolicy = policy
        indexedSegments = Self.buildIndexedSegments(
            text: text,
            policy: policy,
            projectPath: projectPath
        )
    }

    nonisolated static func buildIndexedSegments(
        text: String,
        policy: MarkdownSafetyPolicy,
        projectPath _: String? = nil
    ) -> [IndexedSegment] {
        let renderedText = MarkdownMessageProcessor.sanitize(text, policy: policy)
        let linkifiedText = MarkdownMessageProcessor.linkifyProjectFileReferences(renderedText)
        let segments = MarkdownMessageProcessor.parseSegments(linkifiedText)
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
            if let fileURL = MarkdownMessageProcessor.resolveProjectFileURL(url, projectPath: projectPath) {
                #if canImport(AppKit)
                    NSWorkspace.shared.open(fileURL)
                    return .handled
                #else
                    return .systemAction(fileURL)
                #endif
            }
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
