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
        .overlay(alignment: .top) {
            if let notice = viewModel.contextTruncationNotice {
                Text(notice)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.contextTruncationNotice)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.contextTruncationNotice)
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
                    // ForEach directly over messages — no Array allocation, stable IDs.
                    ForEach(viewModel.messages) { msg in
                        // Context window divider appears above the first in-context message.
                        if msg.id == viewModel.contextCutoffMessageId {
                            HStack(spacing: 8) {
                                Rectangle().frame(height: 1.5).foregroundStyle(.orange.opacity(0.4))
                                Text("Above messages are outside the context window")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                                    .fixedSize()
                                Rectangle().frame(height: 1.5).foregroundStyle(.orange.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }

                        MessageBubble(
                            message: msg,
                            isOutOfContext: viewModel.outOfContextMessageIds.contains(msg.id)
                        )
                        .equatable()
                        .id(msg.id)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 20)
            }
            // Animated scroll when a new message is added.
            .onChange(of: viewModel.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // Cheap Int comparison (not String) to follow streaming content.
            .onChange(of: viewModel.streamTick) {
                proxy.scrollTo("bottom", anchor: .bottom)
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
