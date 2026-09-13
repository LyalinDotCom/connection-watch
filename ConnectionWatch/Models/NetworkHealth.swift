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
        isICMPBlocked: Bool? = nil,
        previousState: ConnectionState = .good
    ) -> NetworkHealth {
        // Offline check: link down OR both ping and HTTP failed
        if !isConnected || (pingLatency == nil && httpLatency == nil) {
            return NetworkHealth(
                score: 0,
                state: .disconnected,
                ratingLabel: "Offline",
                reasons: ["Connection unreachable"],
                isInformationalNoteOnly: false,
                isICMPBlocked: false,
                pingLatency: pingLatency,
                jitter: jitter,
                httpLatency: httpLatency,
                downloadSpeedMbps: downloadSpeedMbps,
                recentPacketLoss: recentPacketLoss
            )
        }

        // Single source of truth for ICMP-blocked network detection
        let icmpBlocked = isICMPBlocked ?? (
            pingLatency == nil
            && recentPacketLoss >= 99
            && httpLatency != nil
        )

        var reasons: [String] = []
        var informationalNote = false

        // 1. Ping Latency Score (0-100) — Weight: 35%
        let pingScore: Double
        if let pingLatency {
            if pingLatency <= 25 {
                pingScore = 100
            } else if pingLatency <= goodThreshold {
                let ratio = (pingLatency - 25) / max(1, goodThreshold - 25)
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
            if !icmpBlocked {
                reasons.append("ICMP ping timeout")
            }
        }

        // 2. Stability Score (Packet Loss & Jitter) (0-100) — Weight: 35%
        var stabilityScore: Double = 100
        if !icmpBlocked && recentPacketLoss > 0 {
            stabilityScore -= min(85, recentPacketLoss * 2.5)
            if recentPacketLoss >= 5 {
                reasons.append(String(format: "Packet loss (%.0f%%)", recentPacketLoss))
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

        // 3. HTTP Latency Score (0-100) — Weight: 30% (100% if ICMP blocked)
        let httpScore: Double
        if let httpLatency {
            if httpLatency <= 80 {
                httpScore = 100
            } else if httpLatency <= goodThreshold {
                let ratio = (httpLatency - 80) / max(1, goodThreshold - 80)
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
        } else {
            httpScore = 25
            reasons.append("HTTP probe failed")
        }

        // Weighted composite
        var rawScore: Double
        if icmpBlocked {
            rawScore = httpScore
            if reasons.isEmpty {
                reasons.append("ICMP filtered (using HTTP only)")
                informationalNote = true
            }
        } else {
            rawScore = (pingScore * 0.35)
                + (stabilityScore * 0.35)
                + (httpScore * 0.30)

            // Critical caps so severe issues always trigger Degraded state
            if httpLatency == nil || recentPacketLoss >= 15 {
                rawScore = min(rawScore, 58)
            } else if pingLatency == nil || (pingLatency ?? 0) > goodThreshold || (httpLatency ?? 0) > goodThreshold || recentPacketLoss >= 5 {
                rawScore = min(rawScore, 67)
            }
        }

        let finalScore = max(0, min(100, Int(rawScore.rounded())))

        // Hysteresis dead-band around score 70 to prevent oscillation
        let goodCutoff: Int = (previousState == .degraded) ? 73 : 68

        var state: ConnectionState
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
        } else if finalScore >= 20 {
            state = .degraded
            ratingLabel = "Poor"
        } else {
            state = .disconnected
            ratingLabel = "Poor"
        }

        // R1 Fix: A working connection (early offline check did not fire) is degraded, never "down".
        if state == .disconnected {
            state = .degraded
        }

        let effectiveLoss = icmpBlocked ? 0.0 : recentPacketLoss

        return NetworkHealth(
            score: finalScore,
            state: state,
            ratingLabel: ratingLabel,
            reasons: reasons,
            isInformationalNoteOnly: informationalNote && state == .good,
            isICMPBlocked: icmpBlocked,
            pingLatency: pingLatency,
            jitter: jitter,
            httpLatency: httpLatency,
            downloadSpeedMbps: downloadSpeedMbps,
            recentPacketLoss: effectiveLoss
        )
    }
}
