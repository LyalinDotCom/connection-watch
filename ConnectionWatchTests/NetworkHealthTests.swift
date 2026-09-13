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
            degradedThreshold: 600.0
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
            degradedThreshold: 600.0
        )

        #expect(health.state == .good)
        #expect(health.score == 100)
        #expect(health.ratingLabel == "Excellent")
        #expect(health.isInformationalNoteOnly == true)
        #expect(health.reasons == ["ICMP filtered (using HTTP only)"])
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
            degradedThreshold: 600.0
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
            degradedThreshold: 600.0
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
            degradedThreshold: 600.0
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
            degradedThreshold: 600.0
        )
        #expect(probesFailedHealth.state == .disconnected)
        #expect(probesFailedHealth.score == 0)
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
