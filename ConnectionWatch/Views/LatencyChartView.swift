import SwiftUI
import Charts

enum ChartDisplayMode: String, CaseIterable, Identifiable {
    case wave = "Wave"
    case bars = "Bars"
    case pulse = "Pulse"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wave: return "waveform.path.ecg"
        case .bars: return "chart.bar.xaxis"
        case .pulse: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Fixed geometry for the chart card. Every value here is deliberately constant so that
/// switching display modes cannot reflow, resize, or wrap any part of the card.
enum ChartMetrics {
    /// Height of the plot area itself.
    static let plotHeight: CGFloat = 200
    /// Height of the legend + mode switcher row.
    static let headerHeight: CGFloat = 24
    static let headerToPlotSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 10
    /// Width reserved for each segment of the mode switcher. Sized for the widest
    /// label so the bar does not change width as the selection moves.
    static let modeSegmentWidth: CGFloat = 66
    static let modeSegmentHeight: CGFloat = 18

    /// Total height of the card, used by the empty state so the dashboard does not
    /// jump when the first samples arrive.
    static var cardHeight: CGFloat {
        headerHeight + headerToPlotSpacing + plotHeight + cardPadding * 2
    }
}

struct LatencyChartView: View {
    let history: PingHistory
    var goodThreshold: Double = 200
    var degradedThreshold: Double = 1000

    @State private var displayMode: ChartDisplayMode = .wave
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: ChartMetrics.headerToPlotSpacing) {
            // Chart Header Bar: Legend + Segmented Mode Switcher
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    legendItem("HTTP", color: .blue)
                    legendItem("Ping", color: .cyan)
                    // Jitter is only plotted in pulse mode, but its slot is reserved in
                    // every mode so the row keeps one constant width.
                    legendItem("Jitter", color: .teal.opacity(0.6))
                        .opacity(displayMode == .pulse ? 1 : 0)
                        .accessibilityHidden(displayMode != .pulse)
                }

                Spacer(minLength: 8)

                // Sleek Segmented Mode Pill Bar
                HStack(spacing: 2) {
                    ForEach(ChartDisplayMode.allCases) { mode in
                        ModePillButton(
                            mode: mode,
                            isSelected: displayMode == mode,
                            action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    displayMode = mode
                                }
                            }
                        )
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                // The switcher is a control, not filler: it keeps its size instead of
                // being squeezed by whatever else shares the row.
                .fixedSize()
            }
            .frame(height: ChartMetrics.headerHeight)

            // Main Chart
            Chart {
                let httpEntries = history.entries(ofType: .http)
                let pingEntries = history.entries(ofType: .ping)
                let icmpBlocked = history.isICMPLikelyBlocked

                switch displayMode {
                case .wave:
                    // HTTP probes — blue area & line
                    ForEach(httpEntries.filter(\.succeeded)) { entry in
                        AreaMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0),
                            series: .value("Type", "HTTP")
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.blue.opacity(0.28), .blue.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0),
                            series: .value("Type", "HTTP")
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    }

                    // Ping probes — cyan line & subtle area
                    ForEach(pingEntries.filter(\.succeeded)) { entry in
                        AreaMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0),
                            series: .value("Type", "Ping")
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.cyan.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0),
                            series: .value("Type", "Ping")
                        )
                        .foregroundStyle(.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    }

                case .bars:
                    // Histogram / Bar chart view
                    ForEach(httpEntries.filter(\.succeeded)) { entry in
                        BarMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0)
                        )
                        .position(by: .value("Type", "HTTP"))
                        .foregroundStyle(.blue.opacity(0.75))
                        .cornerRadius(2.5)
                    }

                    ForEach(pingEntries.filter(\.succeeded)) { entry in
                        BarMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0)
                        )
                        .position(by: .value("Type", "Ping"))
                        .foregroundStyle(.cyan.opacity(0.85))
                        .cornerRadius(2.5)
                    }

                case .pulse:
                    // Jitter envelope band + points
                    ForEach(pingEntries.filter(\.succeeded)) { entry in
                        let lat = entry.latency ?? 0
                        let jit = entry.jitter ?? 0
                        AreaMark(
                            x: .value("Time", entry.timestamp),
                            yStart: .value("Min", max(0, lat - jit)),
                            yEnd: .value("Max", lat + jit)
                        )
                        .foregroundStyle(.teal.opacity(0.22))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", lat),
                            series: .value("Type", "Ping")
                        )
                        .foregroundStyle(.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", lat)
                        )
                        .foregroundStyle(.cyan)
                        .symbolSize(24)
                    }

                    ForEach(httpEntries.filter(\.succeeded)) { entry in
                        PointMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Latency", entry.latency ?? 0)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(20)
                    }
                }

                // Failed probes — red dots (exclude .speed entries, and ignore ICMP failures if ICMP is filtered)
                let failedEntries = history.entries.filter { entry in
                    guard entry.probeType != .speed, !entry.succeeded else { return false }
                    if icmpBlocked && entry.probeType == .ping {
                        return false
                    }
                    return true
                }

                ForEach(failedEntries) { entry in
                    PointMark(
                        x: .value("Time", entry.timestamp),
                        y: .value("Latency", maxChartValue * 0.96)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(28)
                }

                // Good threshold rule
                RuleMark(y: .value("Good", goodThreshold))
                    .foregroundStyle(.orange.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Hover Scrubbing Crosshair + Floating Tooltip
                if let hoverDate, let scrubbed = nearestEntrySummary(at: hoverDate) {
                    RuleMark(x: .value("Hover", scrubbed.timestamp))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .annotation(
                            position: .overlay,
                            alignment: .top,
                            spacing: 6,
                            overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                        ) {
                            scrubTooltipView(summary: scrubbed)
                        }
                }
            }
            .chartYScale(domain: 0...maxChartValue)
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
            .chartForegroundStyleScale([
                "HTTP": .blue,
                "Ping": .cyan,
            ])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))ms")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.08))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.05))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { _ in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let date: Date = proxy.value(atX: location.x) {
                                    hoverDate = date
                                }
                            case .ended:
                                hoverDate = nil
                            }
                        }
                }
            }
            .frame(height: ChartMetrics.plotHeight)
            .clipped()
        }
        .padding(ChartMetrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var maxChartValue: Double {
        let maxHTTP = history.entries(ofType: .http).compactMap(\.latency).max() ?? 0
        let maxPingWithJitter = history.entries(ofType: .ping).compactMap { entry -> Double? in
            guard let lat = entry.latency else { return nil }
            return lat + (entry.jitter ?? 0)
        }.max() ?? 0

        let peak = max(maxHTTP, maxPingWithJitter, history.maxLatency ?? 0)
        let calculatedMax = max(peak * 1.25, goodThreshold * 1.6)
        return calculatedMax > 10 ? calculatedMax : 200.0
    }

    private struct ScrubSummary {
        let timestamp: Date
        let pingLatency: Double?
        let jitter: Double?
        let httpLatency: Double?
        let pingFailed: Bool
        let httpFailed: Bool
    }

    private func nearestEntrySummary(at targetDate: Date) -> ScrubSummary? {
        let nonSpeed = history.entries.filter { $0.probeType != .speed }
        guard let nearest = nonSpeed.min(by: { abs($0.timestamp.timeIntervalSince(targetDate)) < abs($1.timestamp.timeIntervalSince(targetDate)) }) else {
            return nil
        }

        // Match companion ping/http sharing the cycle timestamp (or closest within 2.5s)
        let windowEntries = nonSpeed.filter { abs($0.timestamp.timeIntervalSince(nearest.timestamp)) < 2.5 }
        let pingEntry = windowEntries
            .filter { $0.probeType == .ping }
            .min(by: { abs($0.timestamp.timeIntervalSince(nearest.timestamp)) < abs($1.timestamp.timeIntervalSince(nearest.timestamp)) })
        let httpEntry = windowEntries
            .filter { $0.probeType == .http }
            .min(by: { abs($0.timestamp.timeIntervalSince(nearest.timestamp)) < abs($1.timestamp.timeIntervalSince(nearest.timestamp)) })

        return ScrubSummary(
            timestamp: nearest.timestamp,
            pingLatency: pingEntry?.latency,
            jitter: pingEntry?.jitter,
            httpLatency: httpEntry?.latency,
            pingFailed: pingEntry != nil && pingEntry?.latency == nil && !history.isICMPLikelyBlocked,
            httpFailed: httpEntry != nil && httpEntry?.latency == nil
        )
    }

    @ViewBuilder
    private func scrubTooltipView(summary: ScrubSummary) -> some View {
        HStack(spacing: 6) {
            Text(summary.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            if let ping = summary.pingLatency {
                HStack(spacing: 2) {
                    Circle().fill(.cyan).frame(width: 5, height: 5)
                    Text(String(format: "%.0fms", ping))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            } else if summary.pingFailed {
                HStack(spacing: 2) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("Timeout")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            if let http = summary.httpLatency {
                HStack(spacing: 2) {
                    Circle().fill(.blue).frame(width: 5, height: 5)
                    Text(String(format: "%.0fms", http))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            } else if summary.httpFailed {
                HStack(spacing: 2) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("Failed")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

private struct ModePillButton: View {
    let mode: ChartDisplayMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(mode.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            // Fixed size rather than padding: the weight of the label must not change
            // the segment's width, and the label must never wrap.
            .frame(width: ChartMetrics.modeSegmentWidth, height: ChartMetrics.modeSegmentHeight)
            .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .help("Show the \(mode.rawValue.lowercased()) view")
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
