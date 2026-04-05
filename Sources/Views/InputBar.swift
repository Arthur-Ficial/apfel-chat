import SwiftUI

struct InputBar: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.speechInput != nil {
                Button(action: { Task { await viewModel.toggleListening() } }) {
                    Image(systemName: viewModel.speechInput?.isListening == true ? "mic.fill" : "mic")
                        .foregroundStyle(viewModel.speechInput?.isListening == true ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Voice input")
            }

            TextField("Message...", text: $viewModel.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { Task { await viewModel.send() } }

            if viewModel.speechOutput != nil {
                Button(action: {
                    if viewModel.speechOutput?.isSpeaking == true {
                        viewModel.speechOutput?.stop()
                    } else {
                        viewModel.speakLastResponse()
                    }
                }) {
                    Image(systemName: viewModel.speechOutput?.isSpeaking == true ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .foregroundStyle(viewModel.speechOutput?.isSpeaking == true ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Read aloud")
            }

            Button(action: { Task { await viewModel.send() } }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
        }
        .padding(12)
        .background(.white)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(white: 0.9)), alignment: .top)
    }
}
