import Foundation

struct PingSummary: Sendable, Equatable {
    let minLatency: Double?
    let avgLatency: Double?
    let maxLatency: Double?
    let jitter: Double?
    let packetLossPercent: Double?
}

enum PingOutputParser {
    private static let singleTimePattern = /time=(\d+\.?\d*)\s*ms/
    private static let summaryStatsPattern = /round-trip\s+min\/avg\/max\/stddev\s*=\s*(\d+\.?\d*|nan)\/(\d+\.?\d*|nan)\/(\d+\.?\d*|nan)\/(\d+\.?\d*|nan)\s*ms/
    private static let packetLossPattern = /(\d+\.?\d*)%\s+packet loss/

    private static func parseFiniteDouble(_ str: Substring) -> Double? {
        guard let val = Double(str), val.isFinite else { return nil }
        return val
    }

    static func parseLatency(from output: String) -> Double? {
        if let summary = parseSummary(from: output), let avg = summary.avgLatency {
            return avg
        }
        guard let match = output.firstMatch(of: singleTimePattern) else { return nil }
        return parseFiniteDouble(match.1)
    }

    static func parseSummary(from output: String) -> PingSummary? {
        var packetLoss: Double?
        if let lossMatch = output.firstMatch(of: packetLossPattern) {
            packetLoss = parseFiniteDouble(lossMatch.1)
        }

        if let statsMatch = output.firstMatch(of: summaryStatsPattern) {
            let minVal = parseFiniteDouble(statsMatch.1)
            let avgVal = parseFiniteDouble(statsMatch.2)
            let maxVal = parseFiniteDouble(statsMatch.3)
            let stddevVal = parseFiniteDouble(statsMatch.4) ?? (avgVal != nil ? 0.0 : nil)
            return PingSummary(
                minLatency: minVal,
                avgLatency: avgVal,
                maxLatency: maxVal,
                jitter: stddevVal,
                packetLossPercent: packetLoss ?? 0.0
            )
        }

        // Fallback: compute from individual time=X ms matches if summary line wasn't present
        let timeMatches = output.matches(of: singleTimePattern).compactMap { Double($0.1) }
        guard !timeMatches.isEmpty else {
            if let packetLoss {
                return PingSummary(
                    minLatency: nil,
                    avgLatency: nil,
                    maxLatency: nil,
                    jitter: nil,
                    packetLossPercent: packetLoss
                )
            }
            return nil
        }

        let minVal = timeMatches.min()
        let maxVal = timeMatches.max()
        let avgVal = timeMatches.reduce(0, +) / Double(timeMatches.count)
        let variance = timeMatches.map { pow($0 - avgVal, 2) }.reduce(0, +) / Double(timeMatches.count)
        let stddev = sqrt(variance)

        return PingSummary(
            minLatency: minVal,
            avgLatency: avgVal,
            maxLatency: maxVal,
            jitter: stddev,
            packetLossPercent: packetLoss ?? 0.0
        )
    }
}
