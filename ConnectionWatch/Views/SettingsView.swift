import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: StatusViewModel
    var onClose: () -> Void = {}

    @State private var draftPingTarget: String = ""
    @State private var draftPingInterval: Double = 10
    @State private var draftGoodThreshold: Double = 150
    @State private var draftDegradedThreshold: Double = 600
    @State private var validationMessage: String?
    @State private var copiedSkill = false

    private var appDisplayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Connection Watch"
    }

    private var appVersionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.1"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "19"
        return "v\(shortVersion) (build \(buildNumber))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Navigation Header Bar
            HStack(spacing: 8) {
                Button {
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
            VStack(alignment: .leading, spacing: 8) {
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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Network Probes & Thresholds Card
            VStack(alignment: .leading, spacing: 8) {
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
                            handleApplyAndClose()
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
                                handleApplyAndClose()
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
                                handleApplyAndClose()
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
                                handleApplyAndClose()
                            }
                        Text("ms")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // CLI & AI Agent Integration Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CLI & AI AGENT (7-DAY TELEMETRY)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("SQLite WAL")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("connection-watch CLI & Skill")
                            .font(.system(size: 12, weight: .medium))
                        Text("Give AI agents access to 7-day ping, speed & SSID history")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        viewModel.copyAgentSkill()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            copiedSkill = true
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2.0))
                            withAnimation(.easeOut(duration: 0.2)) {
                                copiedSkill = false
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedSkill ? "checkmark.circle.fill" : "sparkles")
                                .foregroundStyle(copiedSkill ? Color.green : Color.accentColor)
                            Text(copiedSkill ? "Copied Skill!" : "Copy Agent Skill")
                        }
                    }
                    .buttonStyle(ModernMacButtonStyle())
                }
            }
            .padding(10)
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
                    handleApplyAndClose()
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
    }

    private func handleApplyAndClose() {
        let hadAdjustments = commitSettings()
        if !hadAdjustments {
            onClose()
        }
    }

    @discardableResult
    private func commitSettings() -> Bool {
        let adjustments = viewModel.applySettings(
            pingTarget: draftPingTarget,
            pingInterval: draftPingInterval,
            goodThreshold: draftGoodThreshold,
            degradedThreshold: draftDegradedThreshold
        )

        draftPingTarget = viewModel.pingTarget
        draftPingInterval = viewModel.pingInterval
        draftGoodThreshold = viewModel.goodThreshold
        draftDegradedThreshold = viewModel.degradedThreshold

        validationMessage = adjustments.isEmpty ? nil : adjustments.joined(separator: " • ")
        return !adjustments.isEmpty
    }
}
