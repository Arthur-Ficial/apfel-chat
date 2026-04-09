import SwiftUI

struct MessageBubble: View {
    let message: Message
    var isOutOfContext: Bool = false

    @State private var showCopied = false
    @State private var copyHover = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                // Bubble
                VStack(alignment: .leading, spacing: 0) {
                    contentView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

                // Metadata + Copy row
                HStack(spacing: 6) {
                    if let ms = message.durationMs {
                        Text("\(ms)ms")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    if let tokens = message.tokenCount {
                        Text("\(tokens) tok")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }

                    if !message.content.isEmpty && !message.isStreaming {
                        Button(action: copyToClipboard) {
                            Text(showCopied ? "Copied" : "Copy")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(showCopied ? .green : copyHover ? .blue : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .onHover { copyHover = $0 }
                    }
                }
                .padding(.horizontal, 4)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
        .saturation(isOutOfContext ? 0.0 : 1.0)
        .opacity(isOutOfContext ? 0.5 : 1.0)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }

    // MARK: - Bubble Shape

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18)
    }

    private var displayContent: String {
        message.content
    }

    // MARK: - Content

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
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks) { block in
                        switch block.type {
                        case .text:
                            Text(MarkdownRenderer.render(block.content))
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        case .code:
                            VStack(alignment: .leading, spacing: 0) {
                                if let lang = block.language {
                                    HStack {
                                        Text(lang)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(white: 0.88))
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(block.content)
                                        .font(.system(size: 12, design: .monospaced))
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

    // MARK: - iMessage-style colors

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .assistant: return Color(white: 0.93)
        case .system: return Color.orange.opacity(0.12)
        }
    }

    private var textColor: Color {
        message.role == .user ? .white : .primary
    }
}
