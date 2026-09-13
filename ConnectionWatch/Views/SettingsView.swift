import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: StatusViewModel

    @State private var draftPingTarget: String = ""
    @State private var draftPingInterval: Double = 10
    @State private var draftGoodThreshold: Double = 150
    @State private var draftDegradedThreshold: Double = 600

    private var appVersionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
        return "v\(shortVersion) (build \(buildNumber))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("Settings")
                    .font(.subheadline.bold())
                Spacer()
                Text(appVersionString)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            LabeledContent("Ping Target") {
                TextField("IP or hostname", text: $draftPingTarget)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit {
                        commitPingTarget()
                    }
            }
            .font(.caption)

            LabeledContent("Interval") {
                HStack(spacing: 4) {
                    TextField("", value: $draftPingInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .onSubmit {
                            commitNumericSettings()
                        }
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            LabeledContent("Good < ") {
                HStack(spacing: 4) {
                    TextField("", value: $draftGoodThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .onSubmit {
                            commitNumericSettings()
                        }
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            LabeledContent("Degraded < ") {
                HStack(spacing: 4) {
                    TextField("", value: $draftDegradedThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .onSubmit {
                            commitNumericSettings()
                        }
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            HStack {
                Spacer()
                Text("ConnectionWatch \(appVersionString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .onAppear {
            draftPingTarget = viewModel.pingTarget
            draftPingInterval = viewModel.pingInterval
            draftGoodThreshold = viewModel.goodThreshold
            draftDegradedThreshold = viewModel.degradedThreshold
        }
        .onDisappear {
            commitPingTarget()
            commitNumericSettings()
        }
    }

    private func commitPingTarget() {
        let trimmed = draftPingTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != viewModel.pingTarget else { return }
        viewModel.pingTarget = trimmed
    }

    private func commitNumericSettings() {
        if draftPingInterval != viewModel.pingInterval {
            viewModel.pingInterval = draftPingInterval
        }
        if draftGoodThreshold != viewModel.goodThreshold {
            viewModel.goodThreshold = draftGoodThreshold
        }
        if draftDegradedThreshold != viewModel.degradedThreshold {
            viewModel.degradedThreshold = draftDegradedThreshold
        }
    }
}
