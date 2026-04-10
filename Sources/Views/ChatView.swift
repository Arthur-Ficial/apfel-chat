import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var isFollowingTail = true

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            if let status = viewModel.serviceStatusMessage {
                statusBanner(status)
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
        .overlay {
            if viewModel.isLoadingConversation {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading conversation...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.contextTruncationNotice)
        .background(Color(white: 0.98))
        .alert("Microphone Access Required", isPresented: $viewModel.micPermissionDenied) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Voice input requires microphone access. Enable it in System Settings → Privacy & Security → Microphone.")
        }
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
                    ForEach(viewModel.messages) { msg in
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

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { isFollowingTail = true }
                        .onDisappear { isFollowingTail = false }
                }
                .padding(.vertical, 20)
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                guard !viewModel.isLoadingConversation else { return }
                guard newCount > oldCount else { return }
                // Always scroll when user sends (last msg is user) — they're at the bottom by definition.
                // For AI messages appearing, respect whether user has scrolled up.
                let userJustSent = viewModel.messages.last?.role == .user
                guard isFollowingTail || newCount <= 2 || userJustSent else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamTick) {
                guard isFollowingTail else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.isLoadingConversation) { _, isLoading in
                guard !isLoading else { return }
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

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.05))
    }
}
