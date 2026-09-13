import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: StatusViewModel
    var onClose: () -> Void = {}

    @State private var draftPingTarget: String = ""
    @State private var draftPingInterval: Double = 10
    @State private var draftGoodThreshold: Double = 150
    @State private var draftDegradedThreshold: Double = 600
    @State private var validationMessage: String?

    private var appDisplayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Connection Watch"
    }

    private var appVersionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "14"
        return "v\(shortVersion) (build \(buildNumber))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Navigation Header Bar
            HStack(spacing: 8) {
                Button {
                    commitPingTarget()
                    commitNumericSettings()
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                    }
                }
                .buttonStyle(ModernMacButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text(appVersionString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }

            // General Settings Card
            VStack(alignment: .leading, spacing: 10) {
                Text("GENERAL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Label("Launch at Login", systemImage: "power")
                        .font(.system(size: 12.5))
                    Spacer()
                    Toggle("", isOn: $viewModel.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Divider().opacity(0.5)

                HStack {
                    Label("State Change Notifications", systemImage: "bell.badge")
                        .font(.system(size: 12.5))
                    Spacer()
                    Toggle("", isOn: $viewModel.notificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Network Probes & Thresholds Card
            VStack(alignment: .leading, spacing: 10) {
                Text("PROBES & THRESHOLDS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Ping Target")
                        .font(.system(size: 12.5))
                    Spacer()
                    TextField("IP or hostname", text: $draftPingTarget)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 145)
                        .onSubmit {
                            commitPingTarget()
                        }
                }

                Divider().opacity(0.5)

                HStack {
                    Text("Poll Interval")
                        .font(.system(size: 12.5))
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("", value: $draftPingInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 56)
                            .onSubmit {
                                commitNumericSettings()
                            }
                        Text("sec")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.5)

                HStack {
                    Text("Good Latency <")
                        .font(.system(size: 12.5))
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("", value: $draftGoodThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 56)
                            .onSubmit {
                                commitNumericSettings()
                            }
                        Text("ms")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.5)

                HStack {
                    Text("Degraded Latency <")
                        .font(.system(size: 12.5))
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("", value: $draftDegradedThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 56)
                            .onSubmit {
                                commitNumericSettings()
                            }
                        Text("ms")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if let validationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text(validationMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer(minLength: 0)

            // Bottom Footer Bar
            HStack {
                Text("\(appDisplayName) \(appVersionString)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Apply & Close") {
                    commitPingTarget()
                    commitNumericSettings()
                    onClose()
                }
                .buttonStyle(ModernMacButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            draftPingTarget = viewModel.pingTarget
            draftPingInterval = viewModel.pingInterval
            draftGoodThreshold = viewModel.goodThreshold
            draftDegradedThreshold = viewModel.degradedThreshold
            validationMessage = nil
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
        let inputInterval = draftPingInterval
        let inputGood = draftGoodThreshold
        let inputDegraded = draftDegradedThreshold

        viewModel.pingInterval = inputInterval
        viewModel.goodThreshold = inputGood
        viewModel.degradedThreshold = inputDegraded

        let actualInterval = viewModel.pingInterval
        let actualGood = viewModel.goodThreshold
        let actualDegraded = viewModel.degradedThreshold

        draftPingInterval = actualInterval
        draftGoodThreshold = actualGood
        draftDegradedThreshold = actualDegraded

        var adjustments: [String] = []
        if inputInterval != actualInterval {
            adjustments.append("Interval clamped to \(Int(actualInterval))s (5–120s)")
        }
        if inputGood != actualGood {
            adjustments.append("Good threshold clamped to \(Int(actualGood))ms")
        }
        if inputDegraded != actualDegraded {
            adjustments.append("Degraded set to ≥ Good + 50ms (\(Int(actualDegraded))ms)")
        }

        validationMessage = adjustments.isEmpty ? nil : adjustments.joined(separator: " • ")
    }
}
