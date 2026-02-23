import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: StatusViewModel

    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                Circle()
                    .fill(viewModel.currentState.color)
                    .frame(width: 12, height: 12)
                Text(viewModel.currentState.label)
                    .font(.headline)
                Spacer()
            }

            // Dual probe readout
            HStack(spacing: 16) {
                probeReadout(
                    label: "HTTP",
                    latency: viewModel.latestHTTPLatency,
                    detail: viewModel.latestHTTPEndpoint.map { shortHost($0) }
                )
                Divider().frame(height: 30)
                probeReadout(
                    label: "Ping",
                    latency: viewModel.latestPingLatency,
                    detail: viewModel.pingTarget
                )
            }

            Divider()

            // Chart
            if !viewModel.history.isEmpty {
                LatencyChartView(
                    history: viewModel.history,
                    goodThreshold: viewModel.goodThreshold,
                    degradedThreshold: viewModel.degradedThreshold
                )
            } else {
                Text("Collecting data...")
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            }

            // Stats row
            if !viewModel.history.isEmpty {
                HStack(spacing: 16) {
                    statItem("Avg", value: viewModel.history.averageLatency)
                    statItem("Min", value: viewModel.history.minLatency)
                    statItem("Max", value: viewModel.history.maxLatency)
                    Spacer()
                    Text(String(format: "Loss: %.1f%%", viewModel.history.packetLoss))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Bottom bar
            HStack {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }

            if showSettings {
                SettingsView(viewModel: viewModel)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func probeReadout(label: String, latency: Double?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(latency != nil ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            if let latency {
                Text(String(format: "%.0fms", latency))
                    .font(.system(.callout, design: .monospaced))
            } else {
                Text("Failed")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func statItem(_ label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value.map { String(format: "%.0fms", $0) } ?? "—")
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func shortHost(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host() else {
            return urlString
        }
        return host
    }
}
