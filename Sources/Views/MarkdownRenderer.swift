import Foundation
import SwiftUI

enum MarkdownRenderer {
    struct ContentBlock: Identifiable {
        enum BlockType: String { case text, code }
        let type: BlockType
        let content: String
        let language: String?
        let rendered: AttributedString?
        let id: String
    }

    struct CachedRender {
        let isJSON: Bool
        let prettyJSON: String
        let blocks: [ContentBlock]
    }

    @MainActor private static var cache: [String: CachedRender] = [:]
    @MainActor private static var cacheOrder: [String] = []
    private static let cacheLimit = 300

    @MainActor
    static func cachedRender(for content: String) -> CachedRender {
        if let hit = cache[content] {
            touch(content)
            return hit
        }

        let result = compute(for: content)
        cache[content] = result
        touch(content)
        trimCacheIfNeeded()
        return result
    }

    private static func compute(for content: String) -> CachedRender {
        if isJSON(content) {
            return CachedRender(isJSON: true, prettyJSON: prettyJSON(content), blocks: [])
        }
        return CachedRender(isJSON: false, prettyJSON: "", blocks: parseBlocks(content))
    }

    static func parseBlocks(_ markdown: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeContent = ""
        var codeLanguage: String?
        var blockIndex = 0

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if inCodeBlock {
                    blocks.append(ContentBlock(
                        type: .code,
                        content: codeContent.trimmingCharacters(in: .newlines),
                        language: codeLanguage,
                        rendered: nil,
                        id: blockID(type: .code, index: blockIndex, content: codeContent, language: codeLanguage)
                    ))
                    blockIndex += 1
                    codeContent = ""
                    codeLanguage = nil
                    inCodeBlock = false
                } else {
                    let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        blocks.append(ContentBlock(
                            type: .text,
                            content: trimmed,
                            language: nil,
                            rendered: render(trimmed),
                            id: blockID(type: .text, index: blockIndex, content: trimmed, language: nil)
                        ))
                        blockIndex += 1
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
            blocks.append(ContentBlock(
                type: .code,
                content: codeContent,
                language: codeLanguage,
                rendered: nil,
                id: blockID(type: .code, index: blockIndex, content: codeContent, language: codeLanguage)
            ))
            blockIndex += 1
        }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(ContentBlock(
                type: .text,
                content: trimmed,
                language: nil,
                rendered: render(trimmed),
                id: blockID(type: .text, index: blockIndex, content: trimmed, language: nil)
            ))
        }

        return blocks
    }

    static func render(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
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

    @MainActor
    private static func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    @MainActor
    private static func trimCacheIfNeeded() {
        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private static func blockID(
        type: ContentBlock.BlockType,
        index: Int,
        content: String,
        language: String?
    ) -> String {
        "\(type.rawValue)-\(index)-\(language ?? "plain")-\(content.hashValue)"
    }
}
