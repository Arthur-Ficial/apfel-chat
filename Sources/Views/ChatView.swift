import SwiftUI

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

            InputBar(viewModel: viewModel)
        }
        .background(.white)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Start a conversation")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Private AI on your Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }

                    if viewModel.isStreaming {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(.leading, 16)
                            Spacer()
                        }
                        .id("streaming-indicator")
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(viewModel.messages.last?.id ?? "streaming-indicator", anchor: .bottom)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") { viewModel.errorMessage = nil }
                .font(.caption)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}
