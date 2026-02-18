@testable import CodexChatShared
import XCTest

final class MarkdownMessageViewTests: XCTestCase {
    func testSanitizeKeepsExternalContentInTrustedPolicy() {
        let source = """
        [Docs](https://example.com/docs)
        ![Logo](https://cdn.example.com/logo.png)
        """

        let sanitized = MarkdownMessageProcessor.sanitize(source, policy: .trusted)
        XCTAssertEqual(sanitized, source)
    }

    func testSanitizeBlocksExternalLinksAndImagesInUntrustedPolicy() {
        let source = """
        Normal [Docs](https://example.com/docs)
        Local [Guide](docs/guide.md)
        ![Logo](https://cdn.example.com/logo.png)
        ![Local](assets/logo.png)
        """

        let sanitized = MarkdownMessageProcessor.sanitize(source, policy: .untrusted)

        XCTAssertTrue(sanitized.contains("Docs _(external link blocked in untrusted project)_"))
        XCTAssertTrue(sanitized.contains("[Guide](docs/guide.md)"))
        XCTAssertTrue(sanitized.contains("External image blocked in untrusted project"))
        XCTAssertTrue(sanitized.contains("![Local](assets/logo.png)"))
    }

    func testSanitizeLeavesCodeFenceContentUntouched() {
        let source = """
        ```bash
        echo '[Docs](https://example.com/docs)'
        ```
        """

        let sanitized = MarkdownMessageProcessor.sanitize(source, policy: .untrusted)
        XCTAssertEqual(sanitized, source)
    }

    func testParseSegmentsSplitsMermaidAndMarkdown() {
        let source = """
        Intro text

        ```mermaid
        classDiagram
        Animal <|-- Duck
        ```

        Outro text
        """

        let segments = MarkdownMessageProcessor.parseSegments(source)
        XCTAssertEqual(segments.count, 3)

        guard case let .markdown(first) = segments[0] else {
            XCTFail("Expected markdown intro")
            return
        }

        guard case let .mermaid(diagram) = segments[1] else {
            XCTFail("Expected mermaid segment")
            return
        }

        guard case let .markdown(last) = segments[2] else {
            XCTFail("Expected markdown outro")
            return
        }

        XCTAssertTrue(first.contains("Intro text"))
        XCTAssertTrue(diagram.contains("classDiagram"))
        XCTAssertTrue(last.contains("Outro text"))
    }
}
