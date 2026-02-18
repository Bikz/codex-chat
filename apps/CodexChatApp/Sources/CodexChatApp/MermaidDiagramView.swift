import MarkdownUI
import SwiftUI

struct MermaidDiagramView: View {
    let source: String

    var body: some View {
        if let flowchart = MermaidFlowchartParser.parse(source) {
            flowchartView(flowchart)
        } else if let sequence = MermaidSequenceParser.parse(source) {
            sequenceView(sequence)
        } else if let classDiagram = MermaidClassParser.parse(source) {
            classDiagramView(classDiagram)
        } else if let erDiagram = MermaidERParser.parse(source) {
            erDiagramView(erDiagram)
        } else {
            unsupportedDiagramView
        }
    }

    private func flowchartView(_ diagram: MermaidFlowchartDiagram) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flowchart (\(diagram.direction))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if diagram.edges.isEmpty {
                ForEach(diagram.nodes, id: \.id) { node in
                    HStack(spacing: 8) {
                        nodeBadge(text: node.label)
                    }
                }
            } else {
                ForEach(Array(diagram.edges.enumerated()), id: \.offset) { _, edge in
                    HStack(spacing: 8) {
                        nodeBadge(text: nodeLabel(id: edge.fromID, in: diagram))
                        Text("->")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if let label = edge.label, !label.isEmpty {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        nodeBadge(text: nodeLabel(id: edge.toID, in: diagram))
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func sequenceView(_ diagram: MermaidSequenceDiagram) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sequence Diagram")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !diagram.participants.isEmpty {
                Text(diagram.participants.map(\.displayName).joined(separator: "  |  "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(diagram.messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 8) {
                    nodeBadge(text: message.fromID)
                    Text(arrowGlyph(for: message.arrow))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    nodeBadge(text: message.toID)
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func classDiagramView(_ diagram: MermaidClassDiagram) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Class Diagram")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !diagram.classes.isEmpty {
                Text(diagram.classes.joined(separator: "  |  "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(diagram.relations.enumerated()), id: \.offset) { _, relation in
                HStack(alignment: .top, spacing: 8) {
                    nodeBadge(text: relation.fromClass)
                    Text(relation.relation)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    nodeBadge(text: relation.toClass)
                    if let label = relation.label, !label.isEmpty {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func erDiagramView(_ diagram: MermaidERDiagram) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ER Diagram")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !diagram.entities.isEmpty {
                Text(diagram.entities.map(\.name).joined(separator: "  |  "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(diagram.relations.enumerated()), id: \.offset) { _, relation in
                HStack(alignment: .top, spacing: 8) {
                    nodeBadge(text: relation.leftEntity)
                    Text(relation.cardinality)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    nodeBadge(text: relation.rightEntity)
                    Text(relation.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private var unsupportedDiagramView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unsupported Mermaid diagram type in native renderer. Showing source.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Markdown(unsupportedMermaidCodeBlock)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func nodeBadge(text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func nodeLabel(id: String, in diagram: MermaidFlowchartDiagram) -> String {
        diagram.nodes.first(where: { $0.id == id })?.label ?? id
    }

    private func arrowGlyph(for arrow: String) -> String {
        if arrow.contains("--") {
            return "~>"
        }
        return "->"
    }

    private var unsupportedMermaidCodeBlock: String {
        "```mermaid\n\(source)\n```"
    }
}
