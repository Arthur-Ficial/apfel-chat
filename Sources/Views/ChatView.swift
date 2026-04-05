import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            if viewModel.isAnalyzingImage {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    Text("Analyzing image with auge...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.05))
            }

            InputBar(viewModel: viewModel)
        }
        .background(Color(white: 0.98))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.lowercased()
                let imageExts = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "pdf"]
                guard imageExts.contains(ext) else { return }
                Task { @MainActor in
                    await viewModel.handleImageDrop(urls: [url])
                }
            }
            return true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Color(white: 0.8))
            Text("Start a conversation")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Private AI on your Mac")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("Press \u{2318}N for new chat")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, msg in
                        // Context window divider
                        if let cutoff = viewModel.contextCutoffIndex, index == cutoff {
                            HStack(spacing: 8) {
                                Rectangle().frame(height: 1).foregroundStyle(Color(white: 0.85))
                                Text("context window")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                                Rectangle().frame(height: 1).foregroundStyle(Color(white: 0.85))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }

                        MessageBubble(
                            message: msg,
                            isOutOfContext: {
                                guard let cutoff = viewModel.contextCutoffIndex else { return false }
                                return index < cutoff
                            }()
                        )
                        .id(msg.id)
                    }

                    if viewModel.isStreaming {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .id("streaming")
                    }
                }
                .padding(.vertical, 20)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(viewModel.messages.last?.id ?? "streaming", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.content) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.06))
    }
}
