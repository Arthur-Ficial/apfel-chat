import Testing
import Foundation
@testable import apfel_chat

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {

    @Test("Renders plain text")
    func plainText() throws {
        let result = MarkdownRenderer.render("Hello world")
        #expect(!result.characters.isEmpty)
    }

    @Test("Detects code blocks")
    func codeBlocks() {
        let md = """
        Here is some code:
        ```swift
        let x = 42
        ```
        """
        let blocks = MarkdownRenderer.parseBlocks(md)
        #expect(blocks.count == 2)
        #expect(blocks[0].type == .text)
        #expect(blocks[1].type == .code)
        #expect(blocks[1].language == "swift")
        #expect(blocks[1].content.contains("let x = 42"))
    }

    @Test("Detects JSON and pretty-prints")
    func jsonDetection() {
        let json = #"{"name":"test","value":42}"#
        #expect(MarkdownRenderer.isJSON(json) == true)
        let pretty = MarkdownRenderer.prettyJSON(json)
        #expect(pretty.contains("\"name\""))
        #expect(pretty.contains("\n"))
    }

    @Test("Non-JSON returns false")
    func notJSON() {
        #expect(MarkdownRenderer.isJSON("Hello world") == false)
        #expect(MarkdownRenderer.isJSON("") == false)
    }

    @Test("Parses mixed content blocks")
    func mixedBlocks() {
        let md = """
        # Title
        Some text here.

        ```python
        print("hello")
        ```

        More text.
        """
        let blocks = MarkdownRenderer.parseBlocks(md)
        #expect(blocks.count == 3)
        #expect(blocks[0].type == .text)
        #expect(blocks[1].type == .code)
        #expect(blocks[1].language == "python")
        #expect(blocks[2].type == .text)
    }
}
