import SwiftUI

struct SettingsPanel: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("General") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", viewModel.temperature ?? 0.7))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: temperatureBinding, in: 0...2, step: 0.1)
                }
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    TextField("default", value: $viewModel.maxTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("JSON Mode", isOn: $viewModel.jsonMode)
            }

            Section("Speech") {
                Picker("Language", selection: $viewModel.ttsLanguage) {
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("German").tag("de-DE")
                    Text("French").tag("fr-FR")
                    Text("Spanish").tag("es-ES")
                    Text("Italian").tag("it-IT")
                    Text("Portuguese (BR)").tag("pt-BR")
                    Text("Japanese").tag("ja-JP")
                }
                Toggle("Auto-speak responses", isOn: $viewModel.autoSpeak)
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Server URL", text: $viewModel.baseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Model Name", text: $viewModel.modelName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Seed")
                    Spacer()
                    TextField("random", value: $viewModel.seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 450)
        .onDisappear { viewModel.save() }
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { viewModel.temperature ?? 0.7 },
            set: { viewModel.temperature = $0 }
        )
    }
}
