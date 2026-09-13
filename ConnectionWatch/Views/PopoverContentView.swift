import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: StatusViewModel

    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status & Network Health Header
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(viewModel.currentState.color)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(viewModel.currentState.label)
                            .font(.headline)
                        Text(viewModel.interfaceName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if viewModel.isPaused {
                        Text("Monitoring paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Health: \(viewModel.health.score)% • \(viewModel.health.ratingLabel)")
                            .font(.caption)
                            .foregroundStyle(viewModel.currentState.color)
                    }
                }

                Spacer()

                // Pause / Resume button
                Button {
                    viewModel.togglePause()
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
                .help(viewModel.isPaused ? "Resume monitoring" : "Pause monitoring")

                // Refresh button
                Button {
                    viewModel.refreshNow()
                } label: {
                    if viewModel.isProbing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isPaused)
                .help("Check ping and HTTP latency now")
            }

            // Diagnostic alert or informational banner
            if !viewModel.isPaused && !viewModel.health.reasons.isEmpty {
                let isNote = viewModel.health.isInformationalNoteOnly
                HStack(spacing: 6) {
                    Image(systemName: isNote ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isNote ? Color.secondary : viewModel.currentState.color)
                        .font(.caption)
                    Text(viewModel.health.reasons.joined(separator: " • "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((isNote ? Color.secondary : viewModel.currentState.color).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Triple probe readout: Ping | HTTP | Download Speed (on-demand)
            HStack(spacing: 12) {
                pingReadout()
                Divider().frame(height: 36)
                httpReadout()
                Divider().frame(height: 36)
                downloadReadout()
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
                    let loss = viewModel.recentPacketLoss
                    Text(String(format: "Loss: %.1f%%", loss))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(loss > 0 ? Color.orange : Color.secondary)
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

                Button {
                    viewModel.togglePause()
                } label: {
                    Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.caption)
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
        .frame(width: 360)
    }

    private func pingReadout() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.latestPingLatency != nil ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text("Ping")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            if let latency = viewModel.latestPingLatency {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0fms", latency))
                        .font(.system(.callout, design: .monospaced))
                    if let jitter = viewModel.latestJitter {
                        Text(String(format: "±%.0f", jitter))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Failed")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Text(viewModel.pingTarget)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func httpReadout() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.latestHTTPLatency != nil ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text("HTTP")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            if let latency = viewModel.latestHTTPLatency {
                Text(String(format: "%.0fms", latency))
                    .font(.system(.callout, design: .monospaced))
            } else {
                Text("Failed")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Text(viewModel.latestHTTPEndpoint.map { shortHost($0) } ?? "probe")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func downloadReadout() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.latestDownloadSpeedMbps != nil ? Color.blue : Color.secondary)
                    .frame(width: 6, height: 6)
                Text("Download")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            if let mbps = viewModel.latestDownloadSpeedMbps {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f Mbps", mbps))
                        .font(.system(.callout, design: .monospaced))
                    if let date = viewModel.latestDownloadSpeedDate {
                        Text(relativeAgeString(from: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if viewModel.isTestingSpeed {
                Text("Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("On demand")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                viewModel.runSpeedTestNow()
            } label: {
                Text(viewModel.isTestingSpeed ? "Running..." : "Test speed")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isTestingSpeed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func relativeAgeString(from date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 45 {
            return "just now"
        } else if elapsed < 3600 {
            return "\(elapsed / 60)m ago"
        } else {
            return "\(elapsed / 3600)h ago"
        }
    }

    private func shortHost(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host() else {
            return urlString
        }
        return host
    }
}
