import SwiftUI
import Charts

struct LatencyChartView: View {
    let history: PingHistory
    var goodThreshold: Double = 200
    var degradedThreshold: Double = 1000

    var body: some View {
        Chart {
            let httpEntries = history.entries(ofType: .http)
            let pingEntries = history.entries(ofType: .ping)

            // HTTP probes — blue
            ForEach(httpEntries.filter(\.succeeded)) { entry in
                LineMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Latency", entry.latency ?? 0),
                    series: .value("Type", "HTTP")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            }

            ForEach(httpEntries.filter(\.succeeded)) { entry in
                AreaMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Latency", entry.latency ?? 0),
                    series: .value("Type", "HTTP")
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue.opacity(0.2), .blue.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // Ping probes — cyan
            ForEach(pingEntries.filter(\.succeeded)) { entry in
                LineMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Latency", entry.latency ?? 0),
                    series: .value("Type", "Ping")
                )
                .foregroundStyle(.cyan)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // Failed probes — red dots
            ForEach(history.entries.filter { !$0.succeeded }) { entry in
                PointMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Latency", maxChartValue)
                )
                .foregroundStyle(.red)
                .symbolSize(20)
            }

            // Threshold line
            RuleMark(y: .value("Threshold", goodThreshold))
                .foregroundStyle(.orange.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
        }
        .chartYScale(domain: 0...maxChartValue)
        .chartForegroundStyleScale([
            "HTTP": .blue,
            "Ping": .cyan,
        ])
        .chartLegend(position: .top, alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                legendItem("HTTP", color: .blue)
                legendItem("Ping", color: .cyan)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))ms")
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
                AxisGridLine()
            }
        }
        .frame(height: 160)
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var maxChartValue: Double {
        let maxLatency = history.maxLatency ?? degradedThreshold
        return max(maxLatency * 1.2, goodThreshold * 2)
    }
}
