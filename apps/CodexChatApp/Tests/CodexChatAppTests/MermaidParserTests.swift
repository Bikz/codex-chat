@testable import CodexChatShared
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
        pie
        title Pets adopted by type
        "Dogs" : 386
        """

        XCTAssertNil(MermaidFlowchartParser.parse(unsupported))
        XCTAssertNil(MermaidSequenceParser.parse(unsupported))
        XCTAssertNil(MermaidClassParser.parse(unsupported))
        XCTAssertNil(MermaidERParser.parse(unsupported))
    }

    func testClassParserReadsClassesAndRelationships() {
        let source = """
        classDiagram
        Animal <|-- Duck : inherits
        Animal <|-- Fish
        class Zoo
        Zoo --> Animal : keeps
        """

        guard let diagram = MermaidClassParser.parse(source) else {
            XCTFail("Expected class diagram")
            return
        }

        XCTAssertEqual(diagram.classes, ["Animal", "Duck", "Fish", "Zoo"])
        XCTAssertEqual(diagram.relations.count, 3)
        XCTAssertEqual(diagram.relations[0].relation, "<|--")
        XCTAssertEqual(diagram.relations[0].label, "inherits")
        XCTAssertEqual(diagram.relations[2].fromClass, "Zoo")
    }

    func testERParserReadsEntitiesAndRelationships() {
        let source = """
        erDiagram
        CUSTOMER ||--o{ ORDER : places
        ORDER ||--|{ LINE_ITEM : contains
        CUSTOMER {
          string id
        }
        """

        guard let diagram = MermaidERParser.parse(source) else {
            XCTFail("Expected ER diagram")
            return
        }

        XCTAssertEqual(diagram.entities.map(\.name), ["CUSTOMER", "ORDER", "LINE_ITEM"])
        XCTAssertEqual(diagram.relations.count, 2)
        XCTAssertEqual(diagram.relations[0].cardinality, "||--o{")
        XCTAssertEqual(diagram.relations[0].label, "places")
    }
}
