import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: StatusViewModel

    @State private var showSettings = false
    @State private var showSpeedTestConfirm = false
    @State private var isHoveringSpeedResult = false

    var body: some View {
        ZStack {
            // Layer 1: Main Dashboard
            mainDashboardView
                .scaleEffect(showSettings ? 0.96 : 1.0)
                .blur(radius: showSettings ? 8 : 0)
                .opacity(showSettings ? 0 : 1.0)
                .allowsHitTesting(!showSettings)

            // Layer 2: Spatial Settings Overlay (slides in horizontally, zero vertical resize)
            if showSettings {
                SettingsView(
                    viewModel: viewModel,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                            showSettings = false
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }
        }
        .padding(14)
        .frame(width: 380, height: 470)
        .background(.ultraThinMaterial)
    }

    private var mainDashboardView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Status Header & Quick Controls
            HStack(alignment: .center, spacing: 10) {
                // Status Orb with subtle glow
                ZStack {
                    Circle()
                        .fill(viewModel.currentState.color.opacity(0.25))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(viewModel.currentState.color)
                        .frame(width: 10, height: 10)
                        .shadow(color: viewModel.currentState.color.opacity(0.6), radius: 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(viewModel.currentState.label)
                            .font(.system(size: 14, weight: .semibold))
                        Text(viewModel.interfaceName)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    if viewModel.isPaused {
                        Text("Monitoring paused")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            Text("Health \(viewModel.health.score)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(viewModel.currentState.color)
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(viewModel.health.ratingLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Quick Toolbar Buttons
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            viewModel.togglePause()
                        }
                    } label: {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(ModernIconButtonStyle(active: viewModel.isPaused, activeColor: .orange))
                    .help(viewModel.isPaused ? "Resume monitoring" : "Pause monitoring")

                    Button {
                        viewModel.refreshNow()
                    } label: {
                        if viewModel.isProbing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(ModernIconButtonStyle())
                    .disabled(viewModel.isPaused)
                    .help("Probe Ping & HTTP latency immediately")

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                            showSettings = true
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(ModernIconButtonStyle())
                    .help("Settings (⌘,)")
                    .keyboardShortcut(",", modifiers: .command)
                }
            }

            // 2. Diagnostic Banner (if any issues or ICMP notice)
            if !viewModel.isPaused && !viewModel.health.reasons.isEmpty {
                let isNote = viewModel.health.isInformationalNoteOnly
                HStack(spacing: 6) {
                    Image(systemName: isNote ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isNote ? Color.secondary : viewModel.currentState.color)
                        .font(.system(size: 11))
                    Text(viewModel.health.reasons.joined(separator: " • "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((isNote ? Color.secondary : viewModel.currentState.color).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            // 3. Triple Probe Readout Displays Row (Ping | HTTP | Speed — pure read-only displays)
            HStack(spacing: 8) {
                pingCard()
                httpCard()
                downloadCard()
            }

            // 4. Hero Interactive Multi-Mode Chart
            if !viewModel.history.isEmpty {
                LatencyChartView(
                    history: viewModel.history,
                    goodThreshold: viewModel.goodThreshold,
                    degradedThreshold: viewModel.degradedThreshold
                )
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Collecting first network samples...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 175)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                )
            }

            // 5. Compact Stats Summary Pill Strip
            if !viewModel.history.isEmpty {
                HStack(spacing: 12) {
                    statBadge("Avg", value: viewModel.history.averageLatency)
                    statBadge("Min", value: viewModel.history.minLatency)
                    statBadge("Max", value: viewModel.history.maxLatency)

                    Spacer()

                    let loss = viewModel.recentPacketLoss
                    HStack(spacing: 4) {
                        Circle()
                            .fill(loss > 0 ? Color.orange : Color.green)
                            .frame(width: 5, height: 5)
                        Text(String(format: "Loss %.1f%%", loss))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(loss > 0 ? Color.orange : Color.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)

            // 6. Bottom Action Bar or Speed Test Confirmation Prompt
            if showSpeedTestConfirm {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .foregroundStyle(.indigo)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Uses up to ~36 MB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            showSpeedTestConfirm = false
                        }
                    }
                    .buttonStyle(ModernMacButtonStyle())
                    .keyboardShortcut(.cancelAction)

                    Button("Start Test") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            showSpeedTestConfirm = false
                        }
                        viewModel.runSpeedTestNow()
                    }
                    .buttonStyle(ModernMacButtonStyle(prominent: true, tintColor: .indigo))
                    .keyboardShortcut(.defaultAction)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            showSpeedTestConfirm = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if viewModel.isTestingSpeed {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: "speedometer")
                            }
                            Text(viewModel.isTestingSpeed ? "Testing..." : "Test Speed")
                        }
                    }
                    .buttonStyle(ModernMacButtonStyle(prominent: true, tintColor: .indigo))
                    .disabled(viewModel.isTestingSpeed || viewModel.isPaused)
                    .help("Run multi-stage download benchmark")

                    Spacer()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                            Text("Quit")
                        }
                    }
                    .buttonStyle(ModernMacButtonStyle())
                    .keyboardShortcut("q", modifiers: .command)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Pure Read-Only Metric Displays

    private func pingCard() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.latestPingLatency != nil ? Color.cyan : Color.red)
                    .frame(width: 6, height: 6)
                Text("PING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if let latency = viewModel.latestPingLatency {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.0f", latency))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("ms")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let jitter = viewModel.latestJitter {
                        Text(String(format: "±%.0f", jitter))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(viewModel.health.isICMPBlocked ? "Filtered" : "Failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.health.isICMPBlocked ? Color.secondary : Color.red)
            }

            Text(viewModel.pingTarget)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticMetricCard()
    }

    private func httpCard() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.latestHTTPLatency != nil ? Color.blue : Color.red)
                    .frame(width: 6, height: 6)
                Text("HTTP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if let latency = viewModel.latestHTTPLatency {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.0f", latency))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("ms")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }

            Text(viewModel.latestHTTPEndpoint.map { shortHost($0) } ?? "probe")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticMetricCard()
    }

    private func downloadCard() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.latestDownloadSpeedMbps != nil ? Color.indigo : Color.secondary)
                    .frame(width: 6, height: 6)
                Text("SPEED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if let mbps = viewModel.latestDownloadSpeedMbps {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", mbps))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Mbps")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isTestingSpeed {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                    Text("Testing...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if isHoveringSpeedResult, let bytes = viewModel.latestSpeedBytesTransferred {
                Text("Used \(formattedBytes(bytes))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let date = viewModel.latestDownloadSpeedDate {
                Text(relativeAgeString(from: date))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .transition(.opacity)
            } else {
                Text("Not tested yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticMetricCard()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHoveringSpeedResult = hovering
            }
        }
        .help(
            viewModel.latestSpeedBytesTransferred.map {
                "Last speed test transferred \(formattedBytes($0)) of data"
            } ?? "Speed test has not been run yet"
        )
    }

    private func statBadge(_ label: String, value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0fms", $0) } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func shortHost(_ urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host() {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return urlString
    }

    private func relativeAgeString(from date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 5 {
            return "Just now"
        } else if elapsed < 60 {
            return "\(elapsed)s ago"
        } else {
            return "\(elapsed / 60)m ago"
        }
    }

    private func formattedBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB", mb)
    }
}
