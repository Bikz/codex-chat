@testable import CodexChatApp
import XCTest

final class MermaidParserTests: XCTestCase {
    func testFlowchartParserReadsDirectionNodesAndEdges() {
        let source = """
        flowchart LR
        A[Start] -->|ok| B{Decision}
        B --> C[Done]
        """

        guard let diagram = MermaidFlowchartParser.parse(source) else {
            XCTFail("Expected flowchart diagram")
            return
        }

        XCTAssertEqual(diagram.direction, "LR")
        XCTAssertEqual(diagram.nodes.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(diagram.nodes.map(\.label), ["Start", "Decision", "Done"])
        XCTAssertEqual(diagram.edges.count, 2)
        XCTAssertEqual(diagram.edges.first?.label, "ok")
        XCTAssertEqual(diagram.edges.first?.fromID, "A")
        XCTAssertEqual(diagram.edges.first?.toID, "B")
    }

    func testSequenceParserReadsParticipantsAndMessages() {
        let source = """
        sequenceDiagram
        participant Alice as Alice Doe
        participant Bob
        Alice->>Bob: Hello Bob
        Bob-->>Alice: Ack
        """

        guard let diagram = MermaidSequenceParser.parse(source) else {
            XCTFail("Expected sequence diagram")
            return
        }

        XCTAssertEqual(diagram.participants.count, 2)
        XCTAssertEqual(diagram.participants[0].id, "Alice")
        XCTAssertEqual(diagram.participants[0].displayName, "Alice Doe")
        XCTAssertEqual(diagram.participants[1].id, "Bob")
        XCTAssertEqual(diagram.messages.count, 2)
        XCTAssertEqual(diagram.messages[0].fromID, "Alice")
        XCTAssertEqual(diagram.messages[0].toID, "Bob")
        XCTAssertEqual(diagram.messages[0].text, "Hello Bob")
        XCTAssertEqual(diagram.messages[1].arrow, "-->>")
    }

    func testUnsupportedMermaidTypesReturnNilFromParsers() {
        let unsupported = """
        classDiagram
        Animal <|-- Duck
        """

        XCTAssertNil(MermaidFlowchartParser.parse(unsupported))
        XCTAssertNil(MermaidSequenceParser.parse(unsupported))
    }
}
