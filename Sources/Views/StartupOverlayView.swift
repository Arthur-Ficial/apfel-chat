import SwiftUI

struct StartupOverlayView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(StartupWelcomeContent.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(StartupWelcomeContent.subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(StartupWelcomeContent.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(StartupWelcomeContent.engineSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                bulletRow(icon: "airplane", text: StartupWelcomeContent.bullets[0])
                bulletRow(icon: "lock.shield", text: StartupWelcomeContent.bullets[1])
                bulletRow(icon: "person.crop.circle.badge.checkmark", text: StartupWelcomeContent.bullets[2])
            }

            Toggle(isOn: $viewModel.checkUpdatesOnLaunch) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check for updates on launch")
                    Text("If you're offline, nothing is shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Link("About apfel", destination: StartupWelcomeContent.engineURL)
                Spacer()
                Button("Continue") {
                    Task { await viewModel.dismissStartupOverlay() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 560)
        .interactiveDismissDisabled()
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
