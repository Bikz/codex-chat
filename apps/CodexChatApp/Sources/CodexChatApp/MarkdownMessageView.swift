import SwiftUI

struct MarkdownMessageView: View {
    private enum Segment: Hashable {
        case markdown(String)
        case mermaid(String)
    }

    let text: String

    private var segments: [Segment] {
        Self.parseSegments(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .markdown(markdown):
                    markdownText(markdown)
                case let .mermaid(source):
                    MermaidDiagramView(source: source)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func markdownText(_ markdown: String) -> some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func parseSegments(_ input: String) -> [Segment] {
        let lines = input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var segments: [Segment] = []
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
}
