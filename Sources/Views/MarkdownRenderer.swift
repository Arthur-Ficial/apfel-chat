import Foundation
import SwiftUI

enum MarkdownRenderer {
    struct ContentBlock: Identifiable {
        let id = UUID()
        let type: BlockType
        let content: String
        let language: String?

        enum BlockType { case text, code }
    }

    static func parseBlocks(_ markdown: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeContent = ""
        var codeLanguage: String?

        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if inCodeBlock {
                    blocks.append(ContentBlock(type: .code, content: codeContent.trimmingCharacters(in: .newlines), language: codeLanguage))
                    codeContent = ""
                    codeLanguage = nil
                    inCodeBlock = false
                } else {
                    let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        blocks.append(ContentBlock(type: .text, content: trimmed, language: nil))
                    }
                    currentText = ""
                    let lang = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                if !codeContent.isEmpty { codeContent += "\n" }
                codeContent += line
            } else {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            }
        }

        if inCodeBlock && !codeContent.isEmpty {
            blocks.append(ContentBlock(type: .code, content: codeContent, language: codeLanguage))
        }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(ContentBlock(type: .text, content: trimmed, language: nil))
        }

        return blocks
    }

    static func render(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }

    static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return text }
        return str
    }
}
