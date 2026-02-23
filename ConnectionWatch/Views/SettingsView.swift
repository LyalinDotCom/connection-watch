import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: StatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Settings")
                .font(.subheadline.bold())

            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)

            LabeledContent("Ping Target") {
                TextField("IP or hostname", text: $viewModel.pingTarget)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }
            .font(.caption)

            LabeledContent("Interval") {
                HStack(spacing: 4) {
                    TextField("", value: $viewModel.pingInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            LabeledContent("Good < ") {
                HStack(spacing: 4) {
                    TextField("", value: $viewModel.goodThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            LabeledContent("Degraded < ") {
                HStack(spacing: 4) {
                    TextField("", value: $viewModel.degradedThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}
