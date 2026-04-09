import SwiftUI
import UniformTypeIdentifiers

enum InputFocus {
    case message
}

struct InputBar: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var focused: InputFocus?
    // viewModel.showFilePicker lives on viewModel so API can trigger it

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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.06))
            }
            Divider()
            HStack(alignment: .center, spacing: 10) {
                // Mic button
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

                // Attach image button
                if viewModel.augeService != nil {
                    Button(action: { viewModel.showFilePicker = true }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16))
                            .foregroundStyle(viewModel.isAnalyzingImage ? .blue : .gray)
                            .frame(width: 36, height: 36)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isAnalyzingImage)
                    .help("Attach image")
                    .fileImporter(
                        isPresented: $viewModel.showFilePicker,
                        allowedContentTypes: [.image, .pdf],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            Task { await viewModel.handleImageDrop(urls: [url]) }
                        }
                    }
                }

                // Text input
                TextField("Type a message, press Enter to send...", text: $viewModel.currentInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .focused($focused, equals: .message)
                    .frame(minHeight: 36)
                    .onSubmit {
                        Task {
                            await viewModel.send()
                            focused = .message
                        }
                    }

                // Send button
                Button(action: {
                    Task {
                        await viewModel.send()
                        focused = .message
                    }
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? .white : .gray)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .help("Send message")

                // Audio auto-speak toggle
                if viewModel.speechOutput != nil {
                    Button(action: { viewModel.autoSpeak.toggle() }) {
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
    }
}
