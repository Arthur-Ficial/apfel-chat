import SwiftUI

struct MessageBubble: View {
    let message: Message
    var isOutOfContext: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                contentView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(message.role == .assistant ? Color(white: 0.9) : .clear, lineWidth: 1)
                    )

                HStack(spacing: 6) {
                    if let ms = message.durationMs {
                        Text("\(ms)ms")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    if let tokens = message.tokenCount {
                        Text("\(tokens) tokens")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(.horizontal, 4)
            }

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 16)
        .opacity(isOutOfContext ? 0.35 : 1.0)
    }

    private var displayContent: String {
        message.isStreaming ? message.content + "\u{2588}" : message.content
    }

    @ViewBuilder
    private var contentView: some View {
        if MarkdownRenderer.isJSON(message.content) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(MarkdownRenderer.prettyJSON(message.content))
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
            }
        } else {
            let blocks = MarkdownRenderer.parseBlocks(displayContent)
            if blocks.count == 1 && blocks[0].type == .text {
                Text(MarkdownRenderer.render(displayContent))
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks) { block in
                        switch block.type {
                        case .text:
                            Text(MarkdownRenderer.render(block.content))
                                .font(.body)
                                .textSelection(.enabled)
                        case .code:
                            VStack(alignment: .leading, spacing: 0) {
                                if let lang = block.language {
                                    HStack {
                                        Text(lang)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(white: 0.88))
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(block.content)
                                        .font(.system(size: 13, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(10)
                                }
                                .background(Color(white: 0.93))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.08)
        case .assistant: return .white
        case .system: return Color.orange.opacity(0.08)
        }
    }
}
