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
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 640, minHeight: 520, idealHeight: 620, maxHeight: 860)
        .onDisappear { viewModel.save() }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("About") {
                LabeledContent("Version") {
                    Text(viewModel.currentVersion)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Toggle(isOn: $viewModel.checkUpdatesOnLaunch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates on launch")
                        Text("Runs silently in the background. If you're offline, nothing is shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $viewModel.showWelcomeOnNextStart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show welcome on next start")
                        Text("One-shot toggle for testing. It resets after the welcome screen is shown and dismissed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                switch viewModel.updateState {
                case .idle:
                    Button("Check for Update") {
                        Task { await viewModel.checkForUpdate() }
                    }

                case .checking:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking...").foregroundStyle(.secondary)
                    }

                case .upToDate:
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("You're up to date").foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Again") { Task { await viewModel.checkForUpdate() } }
                            .buttonStyle(.borderless)
                    }

                case .updateAvailable(let version):
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(version) available")
                            if viewModel.isHomebrewInstall {
                                Text("Runs brew upgrade automatically")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Opens the latest release download page")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(viewModel.updateInstallButtonTitle) { viewModel.installUpdate() }
                            .buttonStyle(.borderedProminent)
                    }

                case .installing(let version):
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Installing \(version)...").foregroundStyle(.secondary)
                    }

                case .installed(let version):
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("Version \(version) installed").foregroundStyle(.secondary)
                            }
                            Button("Relaunch to Apply") { viewModel.relaunch() }
                                .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }

                case .error(let message):
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button("Retry") { Task { await viewModel.checkForUpdate() } }
                            .buttonStyle(.borderless)
                    }
                }
            }

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

            Section("Appearance") {
                Picker("Theme", selection: $viewModel.appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
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
