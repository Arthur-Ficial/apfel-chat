import SwiftUI

struct SettingsPanel: View {
    @Bindable var viewModel: SettingsViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TabView {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }

                advancedTab
                    .tabItem { Label("Advanced", systemImage: "wrench") }
            }
        }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, minHeight: 400, idealHeight: 480, maxHeight: 700)
        .onDisappear { viewModel.save() }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Model") {
                LabeledContent {
                    HStack {
                        Slider(value: temperatureBinding, in: 0...2, step: 0.1)
                            .frame(maxWidth: 160)
                        Text(String(format: "%.1f", viewModel.temperature ?? AppDefaults.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                } label: {
                    Text("Temperature")
                }

                LabeledContent("Max Tokens") {
                    HStack(spacing: 6) {
                        TextField("", text: maxTokensBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        if viewModel.maxTokens == nil {
                            Text("no limit")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        } else {
                            Button(action: { viewModel.maxTokens = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.borderless)
                            .help("Reset to no limit")
                        }
                    }
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
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Section("Server") {
                LabeledContent("URL") {
                    TextField("", text: $viewModel.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Model") {
                    TextField("", text: $viewModel.modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Model Behaviour") {
                Toggle(isOn: $viewModel.permissive) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permissive mode")
                        Text("Reduces false refusals from Apple Intelligence (--permissive flag). Takes effect on next launch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Reproducibility") {
                LabeledContent("Seed") {
                    HStack(spacing: 6) {
                        TextField("", value: $viewModel.seed, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        if viewModel.seed == nil {
                            Text("random")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        } else {
                            Button(action: { viewModel.seed = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.borderless)
                            .help("Reset to random")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { viewModel.temperature ?? AppDefaults.temperature },
            set: { viewModel.temperature = $0 }
        )
    }

    private var maxTokensBinding: Binding<String> {
        Binding(
            get: { viewModel.maxTokens.map { "\($0)" } ?? "" },
            set: { str in
                if str.isEmpty {
                    viewModel.maxTokens = nil
                } else if let v = Int(str) {
                    viewModel.maxTokens = max(1, min(4096, v))
                }
            }
        )
    }
}
