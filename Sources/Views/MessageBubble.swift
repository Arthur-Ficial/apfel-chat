import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                contentView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let tokens = message.tokenCount {
                    Text("\(tokens) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        // Check if entire content is JSON
        if MarkdownRenderer.isJSON(message.content) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(MarkdownRenderer.prettyJSON(message.content))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        } else {
            let blocks = MarkdownRenderer.parseBlocks(message.content)
            if blocks.count == 1 && blocks[0].type == .text {
                Text(MarkdownRenderer.render(message.content))
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(blocks) { block in
                        switch block.type {
                        case .text:
                            Text(MarkdownRenderer.render(block.content))
                                .textSelection(.enabled)
                        case .code:
                            VStack(alignment: .leading, spacing: 4) {
                                if let lang = block.language {
                                    Text(lang)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(block.content)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                }
                                .background(Color(white: 0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.1)
        case .assistant: return Color(white: 0.97)
        case .system: return Color.orange.opacity(0.1)
        }
    }
}
