import Foundation
import SwiftUI

struct NetworkHealth: Sendable, Equatable {
    let score: Int                 // 0...100
    let state: ConnectionState     // .good, .degraded, .disconnected, .paused
    let ratingLabel: String        // e.g. "Excellent", "Good", "Fair", "Poor", "Offline"
    let reasons: [String]          // Diagnostic reasons if degraded/poor
    let isInformationalNoteOnly: Bool // True when reasons are informational (e.g. ICMP blocked on healthy HTTP)
    let isICMPBlocked: Bool        // True when ICMP is filtered while HTTP connectivity works
    let pingLatency: Double?
    let jitter: Double?
    let httpLatency: Double?
    let downloadSpeedMbps: Double? // Purely informational (on-demand only, does not affect score)
    let recentPacketLoss: Double   // 0...100% effective packet loss

    static let initial = NetworkHealth(
        score: 100,
        state: .good,
        ratingLabel: "Good",
        reasons: [],
        isInformationalNoteOnly: false,
        isICMPBlocked: false,
        pingLatency: nil,
        jitter: nil,
        httpLatency: nil,
        downloadSpeedMbps: nil,
        recentPacketLoss: 0
    )

    static func evaluate(
        isConnected: Bool,
        pingLatency: Double?,
        jitter: Double?,
        recentPacketLoss: Double,
        httpLatency: Double?,
        downloadSpeedMbps: Double?,
        goodThreshold: Double,
        degradedThreshold: Double,
        isICMPBlocked: Bool,
        recentHTTPFailureRate: Double = 0,
        previousState: ConnectionState = .good
    ) -> NetworkHealth {
        // HTTPProbeService has already tried independent endpoints before reporting failure.
        // Ping reachability (or historical ICMP filtering) cannot prove usable internet access.
        guard isConnected, let httpLatency else {
            let reason = !isConnected ? "Network link unavailable" :
                (pingLatency != nil ? "HTTP checks failed; ping still responds" : "HTTP checks failed; internet unavailable")
            return NetworkHealth(
                score: 0,
                state: .disconnected,
                ratingLabel: "Offline",
                reasons: [reason],
                isInformationalNoteOnly: false,
                isICMPBlocked: false,
                pingLatency: isConnected ? pingLatency : nil,
                jitter: isConnected ? jitter : nil,
                httpLatency: isConnected ? httpLatency : nil,
                downloadSpeedMbps: downloadSpeedMbps,
                recentPacketLoss: isConnected ? recentPacketLoss : 100.0
            )
        }

        let effectiveLoss = (isICMPBlocked && recentPacketLoss >= 100.0) ? 0.0 : recentPacketLoss
        var reasons: [String] = []
        var informationalNote = false
        if recentHTTPFailureRate > 0 {
            reasons.append(String(format: "Recent HTTP failures (%.0f%%)", recentHTTPFailureRate))
        }

        // 1. Ping Latency Score (0-100) — Weight: 35%
        let idealPing = min(25.0, goodThreshold * 0.5)
        let pingScore: Double
        if let pingLatency {
            if pingLatency <= idealPing {
                pingScore = 100
            } else if pingLatency <= goodThreshold {
                let ratio = (pingLatency - idealPing) / max(1, goodThreshold - idealPing)
                pingScore = 100 - (ratio * 25)
            } else if pingLatency <= degradedThreshold {
                let ratio = (pingLatency - goodThreshold) / max(1, degradedThreshold - goodThreshold)
                pingScore = 75 - (ratio * 50)
                reasons.append(String(format: "High ping (%.0fms)", pingLatency))
            } else {
                pingScore = max(5, 25 - (pingLatency - degradedThreshold) / 100)
                reasons.append(String(format: "Very high ping (%.0fms)", pingLatency))
            }
        } else {
            pingScore = 50
            if !isICMPBlocked {
                reasons.append("ICMP ping timeout")
            }
        }

        // 2. Stability Score (Packet Loss & Jitter) (0-100) — Weight: 35%
        var stabilityScore: Double = 100
        if effectiveLoss > 0 {
            stabilityScore -= min(85, effectiveLoss * 2.5)
            if effectiveLoss >= 5 {
                reasons.append(String(format: "Packet loss (%.0f%%)", effectiveLoss))
            }
        }
        if let jitter, jitter > 12 {
            let jitterPenalty = min(35, (jitter - 12) * 0.8)
            stabilityScore -= jitterPenalty
            if jitter >= 25 {
                reasons.append(String(format: "High jitter (±%.0fms)", jitter))
            }
        }
        stabilityScore = max(0, min(100, stabilityScore))

        // 3. HTTP Latency Score (0-100) — Weight: 30% (primary if ICMP blocked)
        let idealHTTP = min(80.0, goodThreshold * 0.8)
        let httpScore: Double
        if httpLatency <= idealHTTP {
            httpScore = 100
        } else if httpLatency <= goodThreshold {
            let ratio = (httpLatency - idealHTTP) / max(1, goodThreshold - idealHTTP)
            httpScore = 100 - (ratio * 25)
        } else if httpLatency <= degradedThreshold {
            let ratio = (httpLatency - goodThreshold) / max(1, degradedThreshold - goodThreshold)
            httpScore = 75 - (ratio * 50)
            reasons.append(String(format: "Slow HTTP (%.0fms)", httpLatency))
        } else {
            // Continuous ramp above degradedThreshold instead of a flat 15 cliff
            httpScore = max(5, 25 - (httpLatency - degradedThreshold) / 100)
            reasons.append(String(format: "Very slow HTTP (%.0fms)", httpLatency))
        }

        // Weighted composite
        var rawScore: Double
        if isICMPBlocked {
            if effectiveLoss > 0 {
                rawScore = (httpScore * 0.70) + (stabilityScore * 0.30)
            } else {
                rawScore = httpScore
            }
            if effectiveLoss >= 15 || recentHTTPFailureRate >= 25 {
                rawScore = min(rawScore, 58)
            } else if httpLatency > goodThreshold || effectiveLoss >= 5 || recentHTTPFailureRate > 0 {
                rawScore = min(rawScore, 67)
            }
            if reasons.isEmpty {
                reasons.append("ICMP filtered (using HTTP only)")
                informationalNote = true
            }
        } else {
            rawScore = (pingScore * 0.35)
                + (stabilityScore * 0.35)
                + (httpScore * 0.30)

            // Critical caps so severe issues always trigger Degraded state
            if effectiveLoss >= 15 || recentHTTPFailureRate >= 25 {
                rawScore = min(rawScore, 58)
            } else if pingLatency == nil || (pingLatency ?? 0) > goodThreshold || httpLatency > goodThreshold || effectiveLoss >= 5 || recentHTTPFailureRate > 0 {
                rawScore = min(rawScore, 67)
            }
        }

        let finalScore = max(0, min(100, Int(rawScore.rounded())))

        // Hysteresis dead-band around score 70 to prevent oscillation
        let goodCutoff: Int = (previousState == .degraded) ? 73 : 68

        let state: ConnectionState
        let ratingLabel: String
        if finalScore >= 85 {
            state = .good
            ratingLabel = "Excellent"
        } else if finalScore >= goodCutoff {
            state = .good
            ratingLabel = "Good"
        } else if finalScore >= 45 {
            state = .degraded
            ratingLabel = "Fair"
        } else {
            state = .degraded
            ratingLabel = "Poor"
        }

        return NetworkHealth(
            score: finalScore,
            state: state,
            ratingLabel: ratingLabel,
            reasons: reasons,
            isInformationalNoteOnly: informationalNote && state == .good,
            isICMPBlocked: isICMPBlocked,
            pingLatency: pingLatency,
            jitter: jitter,
            httpLatency: httpLatency,
            downloadSpeedMbps: downloadSpeedMbps,
            recentPacketLoss: effectiveLoss
        )
    }
}
