import SwiftUI
import UniformTypeIdentifiers

enum InputFocus {
    case message
}

struct InputBar: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var focused: InputFocus?

    var body: some View {
        VStack(spacing: 0) {
            if let speechError = viewModel.speechInput?.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(speechError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { viewModel.speechInput?.errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.06))
            }
            Divider()
            HStack(alignment: .center, spacing: 10) {
                if viewModel.speechInput != nil {
                    Button(action: { Task { await viewModel.toggleListening() } }) {
                        Image(systemName: viewModel.speechInput?.isListening == true ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(viewModel.speechInput?.isListening == true ? .red : .gray)
                            .frame(width: 36, height: 36)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.speechInput?.isListening == true ? "Stop listening" : "Voice input")
                }

                Button(action: {
                    if viewModel.augeService == nil {
                        viewModel.errorMessage = "Image analysis requires auge. Install it with: brew install Arthur-Ficial/tap/auge"
                    } else {
                        viewModel.showFilePicker = true
                    }
                }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(viewModel.isAnalyzingImage ? .blue : (viewModel.augeService == nil ? .gray.opacity(0.6) : .gray))
                        .frame(width: 36, height: 36)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isAnalyzingImage)
                .help(viewModel.augeService == nil
                      ? "Install auge to attach images (brew install Arthur-Ficial/tap/auge)"
                      : "Attach image")
                .fileImporter(
                    isPresented: $viewModel.showFilePicker,
                    allowedContentTypes: [.image, .pdf],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        Task { await viewModel.handleImageDrop(urls: [url]) }
                    }
                }

                TextField(inputPlaceholder, text: $viewModel.currentInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .focused($focused, equals: .message)
                    .frame(minHeight: 36)
                    .onSubmit {
                        if viewModel.isStreaming {
                            viewModel.cancelStreaming()
                        } else {
                            Task {
                                await viewModel.send()
                                focused = .message
                            }
                        }
                    }

                Button(action: {
                    if viewModel.isStreaming {
                        viewModel.cancelStreaming()
                    } else {
                        Task {
                            await viewModel.send()
                            focused = .message
                        }
                    }
                }) {
                    Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(buttonForeground)
                        .frame(width: 36, height: 36)
                        .background(buttonBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.isStreaming && !canSend)
                .help(viewModel.isStreaming ? "Stop response" : "Send message")

                if viewModel.speechOutput != nil {
                    Button(action: { viewModel.toggleAutoSpeak() }) {
                        Image(systemName: viewModel.autoSpeak ? "speaker.wave.2.fill" : "speaker.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(viewModel.autoSpeak ? .white : .gray)
                            .frame(width: 36, height: 36)
                            .background(viewModel.autoSpeak ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.autoSpeak ? "Audio on — tap to mute" : "Audio off — tap to enable")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .onAppear {
            focused = .message
        }
    }

    private var canSend: Bool {
        !viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isStreaming
            && !viewModel.isAnalyzingImage
            && viewModel.isServiceReady
    }

    private var inputPlaceholder: String {
        viewModel.isServiceReady ? "Type a message, press Enter to send..." : "Starting on-device AI..."
    }

    private var buttonForeground: Color {
        if viewModel.isStreaming || canSend {
            return .white
        }
        return .gray
    }

    private var buttonBackground: Color {
        if viewModel.isStreaming || canSend {
            return Color(red: 0.0, green: 0.48, blue: 1.0)
        }
        return Color(nsColor: .controlBackgroundColor)
    }
}
