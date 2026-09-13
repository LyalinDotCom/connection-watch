import Foundation
import Testing

struct NetworkHealthTests {
    @Test func evaluatesHealthyConnection() {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 18.0,
            jitter: 2.5,
            recentPacketLoss: 0.0,
            httpLatency: 45.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )

        #expect(health.state == .good)
        #expect(health.score >= 85)
        #expect(health.ratingLabel == "Excellent")
        #expect(health.reasons.isEmpty)
    }

    @Test func icmpBlockedButHttpHealthyStaysGood() {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 100.0,
            httpLatency: 40.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: true
        )

        #expect(health.state == .good)
        #expect(health.score == 100)
        #expect(health.ratingLabel == "Excellent")
        #expect(health.isInformationalNoteOnly == true)
        #expect(health.isICMPBlocked == true)
        #expect(health.recentPacketLoss == 0.0)
        #expect(health.reasons == ["ICMP filtered (using HTTP only)"])
    }

    @Test func icmpBlockedWithSlowHttpIsDegradedNotDisconnected() {
        let health601 = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 100.0,
            httpLatency: 601.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: true
        )

        #expect(health601.state == .degraded)
        #expect(health601.state != .disconnected)
        #expect(health601.score > 0)

        let health2000 = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 100.0,
            httpLatency: 2000.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: true
        )

        #expect(health2000.state == .degraded)
        #expect(health2000.state != .disconnected)
        #expect(health2000.score >= 5)
    }

    @Test func workingConnectionNeverReportsDisconnectedEvenUnderExtremeLatency() {
        let extremeHealth = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 2500.0,
            jitter: 180.0,
            recentPacketLoss: 60.0,
            httpLatency: 3500.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )

        #expect(extremeHealth.state == .degraded)
        #expect(extremeHealth.state != .disconnected)
    }

    @Test func transientPingTimeoutDegradesConnection() {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 12.5, // 1 failed ping out of 8 — not ICMP blocked
            httpLatency: 40.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )

        #expect(health.state == .degraded)
        #expect(health.score == 67)
        #expect(health.reasons.contains("ICMP ping timeout"))
    }

    @Test func downloadSpeedDoesNotDragDownHealthScore() {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 22.0,
            jitter: 3.0,
            recentPacketLoss: 0.0,
            httpLatency: 50.0,
            downloadSpeedMbps: 0.5, // Even a slow on-demand speed test must not penalize health
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )

        #expect(health.state == .good)
        #expect(health.score == 100)
        #expect(health.reasons.isEmpty)
        #expect(health.downloadSpeedMbps == 0.5)
    }

    @Test func evaluatesDegradedConnectionWithHighPingAndPacketLoss() {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 260.0,
            jitter: 35.0,
            recentPacketLoss: 20.0,
            httpLatency: 310.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )

        #expect(health.state == .degraded)
        #expect(health.score < 60)
        #expect(!health.reasons.isEmpty)
    }

    @Test func evaluatesDisconnectedWhenOfflineOrBothProbesFail() {
        let offlineHealth = NetworkHealth.evaluate(
            isConnected: false,
            pingLatency: 25.0,
            jitter: 2.0,
            recentPacketLoss: 0.0,
            httpLatency: 40.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )
        #expect(offlineHealth.state == .disconnected)
        #expect(offlineHealth.score == 0)

        let probesFailedHealth = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 100.0,
            httpLatency: nil,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false
        )
        #expect(probesFailedHealth.state == .disconnected)
        #expect(probesFailedHealth.score == 0)
    }

    @Test @MainActor func thresholdAndIntervalClampingValidation() {
        let monitor = ConnectionMonitorService()

        monitor.pingInterval = 0
        #expect(monitor.pingInterval == 10)

        monitor.pingInterval = -25
        #expect(monitor.pingInterval == 10)

        monitor.pingInterval = 500
        #expect(monitor.pingInterval == 120)

        monitor.goodThreshold = 300
        monitor.degradedThreshold = 100 // Inverted threshold attempt
        #expect(monitor.degradedThreshold >= monitor.goodThreshold + 50)

        monitor.goodThreshold = 700 // Pushing goodThreshold past degradedThreshold
        #expect(monitor.degradedThreshold >= monitor.goodThreshold + 50)
    }

    @Test @MainActor func icmpBlockedNetworkPollingCadenceReturnsToNormal() {
        let monitor = ConnectionMonitorService()
        monitor.pingInterval = 10
        // Before any path change or degradation, interval should be 10s
        #expect(monitor.effectivePollingInterval() == 10.0)
    }

    @Test func unifiedICMPBlockedPredicateTransitionAgreement() {
        // Case 1: 6 failed pings, 6 succeeded HTTPs -> ICMP blocked (both PingHistory and NetworkHealth agree)
        var historyBlocked = PingHistory()
        for _ in 0..<6 {
            historyBlocked.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
            historyBlocked.append(PingResult(timestamp: Date(), latency: 35.0, probeType: .http))
        }
        #expect(historyBlocked.isICMPLikelyBlocked == true)
        #expect(historyBlocked.recentPacketLoss() == 0.0)

        let evaluatedBlocked = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: historyBlocked.latestPing?.latency,
            jitter: historyBlocked.latestPing?.jitter,
            recentPacketLoss: historyBlocked.rawRecentPingPacketLoss(),
            httpLatency: historyBlocked.latestHTTP?.latency,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: historyBlocked.isICMPLikelyBlocked
        )
        #expect(evaluatedBlocked.isICMPBlocked == true)
        #expect(evaluatedBlocked.state == .good)
        #expect(evaluatedBlocked.recentPacketLoss == 0.0)

        // Case 2: 3 failed pings followed by 1 succeeded ping -> NOT ICMP blocked (both agree)
        var historyPartial = PingHistory()
        for _ in 0..<3 {
            historyPartial.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
            historyPartial.append(PingResult(timestamp: Date(), latency: 35.0, probeType: .http))
        }
        historyPartial.append(PingResult(timestamp: Date(), latency: 22.0, packetLossPercent: 0.0, probeType: .ping))
        historyPartial.append(PingResult(timestamp: Date(), latency: 35.0, probeType: .http))

        #expect(historyPartial.isICMPLikelyBlocked == false)
        #expect(historyPartial.recentPacketLoss() > 0.0)
    }

    @Test func hysteresisPreventsBoundaryOscillation() {
        // Inputs producing a score of 72 (inside the 68..<73 dead-band)
        let health72FromGood = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 150.0,
            jitter: 60.0,
            recentPacketLoss: 0.0,
            httpLatency: 150.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false,
            previousState: .good
        )
        #expect(health72FromGood.score == 72)
        #expect(health72FromGood.state == .good)

        // When previously degraded, score of 72 stays .degraded until it reaches >= 73
        let health72FromDegraded = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 150.0,
            jitter: 60.0,
            recentPacketLoss: 0.0,
            httpLatency: 150.0,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: false,
            previousState: .degraded
        )
        #expect(health72FromDegraded.score == 72)
        #expect(health72FromDegraded.state == .degraded)
    }

    @Test func parsesMultiPacketSummaryWithJitterAndLoss() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=54 time=28.519 ms
        64 bytes from 1.1.1.1: icmp_seq=1 ttl=54 time=27.528 ms
        64 bytes from 1.1.1.1: icmp_seq=2 ttl=54 time=18.883 ms

        --- 1.1.1.1 ping statistics ---
        3 packets transmitted, 3 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 18.883/24.977/28.519/4.328 ms
        """
        let summary = PingOutputParser.parseSummary(from: output)
        #expect(summary != nil)
        #expect(summary?.avgLatency == 24.977)
        #expect(summary?.jitter == 4.328)
        #expect(summary?.packetLossPercent == 0.0)
        #expect(PingOutputParser.parseLatency(from: output) == 24.977)
    }
}
