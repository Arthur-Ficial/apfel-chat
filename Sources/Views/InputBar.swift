import SwiftUI

enum InputFocus {
    case message
}

struct InputBar: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var focused: InputFocus?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 8) {
                // Mic button
                if viewModel.speechInput != nil {
                    Button(action: { Task { await viewModel.toggleListening() } }) {
                        Image(systemName: viewModel.speechInput?.isListening == true ? "stop.circle.fill" : "mic.fill")
                            .font(.body)
                            .foregroundStyle(viewModel.speechInput?.isListening == true ? .red : .gray)
                            .frame(width: 30, height: 30)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.speechInput?.isListening == true ? "Stop listening" : "Voice input")
                }

                // Text input
                TextField("Type a message, press Enter to send...", text: $viewModel.currentInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .focused($focused, equals: .message)
                    .onSubmit {
                        Task { await viewModel.send() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focused = .message
                        }
                    }

                // Send button
                Button(action: {
                    Task { await viewModel.send() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focused = .message
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? .blue : Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .help("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focused = .message
            }
        }
    }

    private var canSend: Bool {
        !viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming
    }
}
