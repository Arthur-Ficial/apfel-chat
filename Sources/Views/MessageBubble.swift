import SwiftUI

struct MessageBubble: View {
    let message: Message
    var isOutOfContext: Bool = false
    /// Optional speak action. When non-nil and the message is a finished
    /// assistant response, a speaker icon is rendered next to Copy.
    var onSpeak: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var showCopied = false
    @State private var copyHover = false
    @State private var speakHover = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    contentView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

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

                        if message.role == .assistant, let onSpeak {
                            Button(action: onSpeak) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 11))
                                    .foregroundStyle(speakHover ? .blue : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .onHover { speakHover = $0 }
                            .help("Speak this response")
                        }
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

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18)
    }

    @ViewBuilder
    private var contentView: some View {
        if message.isStreaming {
            Text(message.content.isEmpty ? " " : message.content)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
        } else {
            let cached = MarkdownRenderer.cachedRender(for: message.content)
            if cached.isJSON {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(cached.prettyJSON)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                }
            } else {
                let blocks = cached.blocks
                if blocks.isEmpty {
                    Text(message.content)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                } else if blocks.count == 1 && blocks[0].type == .text {
                    Text(blocks[0].rendered ?? AttributedString(blocks[0].content))
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(blocks) { block in
                            switch block.type {
                            case .text:
                                Text(block.rendered ?? AttributedString(block.content))
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
                                        .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.88))
                                    }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        Text(block.content)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(10)
                                    }
                                    .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.93))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .assistant: return colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.93)
        case .system: return Color.orange.opacity(0.12)
        }
    }
}

extension MessageBubble: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // onSpeak closures aren't equatable, but their presence/absence is
        // stable across re-renders for a given message, so we ignore them.
        lhs.message == rhs.message && lhs.isOutOfContext == rhs.isOutOfContext
    }
}
