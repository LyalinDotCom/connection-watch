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
        // Just over the HTTP degraded limit, which is derived from the ping limits.
        let httpLimits = NetworkHealth.httpThresholds(goodThreshold: 150.0, degradedThreshold: 600.0)
        let health601 = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 100.0,
            httpLatency: httpLimits.degraded + 1,
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
            httpLatency: httpLimits.degraded + 1400,
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
        // Inputs producing a score of 72 (inside the 68..<73 dead-band): ping and HTTP each at their good limit.
        let httpAtGoodLimit = NetworkHealth.httpThresholds(goodThreshold: 150.0, degradedThreshold: 600.0).good
        let health72FromGood = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 150.0,
            jitter: 60.0,
            recentPacketLoss: 0.0,
            httpLatency: httpAtGoodLimit,
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
            httpLatency: httpAtGoodLimit,
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

    @Test func customLowGoodThresholdProducesDiagnosticReasonsAndNoCliff() {
        let slowHTTP = NetworkHealth.httpThresholds(goodThreshold: 60.0, degradedThreshold: 200.0).good + 10
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 20.0,
            jitter: 2.0,
            recentPacketLoss: 0.0,
            httpLatency: slowHTTP,
            downloadSpeedMbps: nil,
            goodThreshold: 60.0,
            degradedThreshold: 200.0,
            isICMPBlocked: false
        )

        #expect(health.state == .degraded)
        #expect(health.reasons.contains(String(format: "Slow HTTP (%.0fms)", slowHTTP)))
    }

    @Test func failedHttpCycleOnICMPBlockedNetworkIsOffline() {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: nil,
            jitter: nil,
            recentPacketLoss: 20.0,
            httpLatency: nil,
            downloadSpeedMbps: nil,
            goodThreshold: 150.0,
            degradedThreshold: 600.0,
            isICMPBlocked: true
        )

        #expect(health.state == .disconnected)
        #expect(health.score == 0)
        #expect(health.reasons.contains("HTTP checks failed; internet unavailable"))
    }

    @Test(arguments: [ConnectionState.good, .degraded, .disconnected])
    func fastPingCannotOverrideFailedHTTP(previousState: ConnectionState) {
        let health = NetworkHealth.evaluate(
            isConnected: true,
            pingLatency: 5,
            jitter: 1,
            recentPacketLoss: 0,
            httpLatency: nil,
            downloadSpeedMbps: 500,
            goodThreshold: 150,
            degradedThreshold: 600,
            isICMPBlocked: false,
            previousState: previousState
        )

        #expect(health.state == .disconnected)
        #expect(health.score == 0)
        #expect(health.ratingLabel == "Offline")
        #expect(health.pingLatency == 5) // Preserve the diagnostic contrast in the popover/CLI.
        #expect(health.reasons == ["HTTP checks failed; ping still responds"])
    }

    @Test func fastPingCannotHideSlowHTTP() {
        let verySlowHTTP = NetworkHealth.httpThresholds(goodThreshold: 150, degradedThreshold: 600).degraded + 100
        let health = NetworkHealth.evaluate(
            isConnected: true, pingLatency: 5, jitter: 1, recentPacketLoss: 0,
            httpLatency: verySlowHTTP, downloadSpeedMbps: nil,
            goodThreshold: 150, degradedThreshold: 600, isICMPBlocked: false
        )
        #expect(health.state == .degraded)
        #expect(health.reasons.contains(String(format: "Very slow HTTP (%.0fms)", verySlowHTTP)))
    }

    @Test func intermittentHTTPRecoversOnlyAfterCleanWindowEvenWithPerfectPing() {
        var history = PingHistory()
        var previousState = ConnectionState.good
        let httpLatencies: [Double?] = [40, nil] + Array(repeating: 40, count: 8)

        for (index, latency) in httpLatencies.enumerated() {
            history.append(PingResult(timestamp: Date(), latency: 5, packetLossPercent: 0, probeType: .ping))
            history.append(PingResult(timestamp: Date(), latency: latency, probeType: .http))
            let health = NetworkHealth.evaluate(
                isConnected: true, pingLatency: history.latestPing?.latency,
                jitter: 1, recentPacketLoss: history.recentPacketLoss(),
                httpLatency: history.latestHTTP?.latency, downloadSpeedMbps: nil,
                goodThreshold: 150, degradedThreshold: 600, isICMPBlocked: history.isICMPLikelyBlocked,
                recentHTTPFailureRate: history.recentHTTPFailureRate(), previousState: previousState
            )
            let expected: ConnectionState = index == 1 ? .disconnected :
                ((2...8).contains(index) ? .degraded : .good)
            #expect(health.state == expected)
            #expect(history.recentPacketLoss() == 0)
            previousState = health.state
        }
    }

    @Test @MainActor func pingTargetSanitizationStripsURLsAndFlags() {
        #expect(ConnectionMonitorService.sanitizePingTarget("https://1.1.1.1/dns-query") == "1.1.1.1")
        #expect(ConnectionMonitorService.sanitizePingTarget("http://www.google.com/test") == "www.google.com")
        #expect(ConnectionMonitorService.sanitizePingTarget("-f 8.8.8.8") == "f 8.8.8.8")
        #expect(ConnectionMonitorService.sanitizePingTarget("   ") == "1.1.1.1")
    }

    // MARK: - HTTP limits for a probe that opens a new connection

    private static func reading(
        ping: Double? = 20, http: Double? = 40, loss: Double = 0, previousState: ConnectionState = .good
    ) -> NetworkHealth {
        NetworkHealth.evaluate(
            isConnected: true, pingLatency: ping, jitter: 1, recentPacketLoss: loss,
            httpLatency: http, downloadSpeedMbps: nil,
            goodThreshold: 150, degradedThreshold: 600, isICMPBlocked: false,
            previousState: previousState
        )
    }

    @Test func newConnectionHTTPTimeOnHealthyLinkScoresFull() {
        // On a link with a single-digit ping, a new HTTPS connection took a median of 84ms to Google
        // and 166ms to Apple. Under the old shared limit of 150ms the latter read as Degraded.
        let health = Self.reading(ping: 8, http: 166)
        #expect(health.state == .good)
        #expect(health.score == 100)
        #expect(health.reasons.isEmpty)
    }

    @Test func httpIsJudgedAgainstItsOwnLimitsNotThePingLimits() {
        let limits = NetworkHealth.httpThresholds(goodThreshold: 150, degradedThreshold: 600)
        #expect(limits.good > 150)
        #expect(limits.degraded > limits.good)

        let under = Self.reading(http: limits.good - 1)
        #expect(under.state == .good)
        #expect(under.reasons.isEmpty)

        let over = Self.reading(http: limits.good + 1)
        #expect(over.state == .degraded)
        #expect(over.reasons == [String(format: "Slow HTTP (%.0fms)", limits.good + 1)])

        let farOver = Self.reading(http: limits.degraded + 1)
        #expect(farOver.state == .degraded)
        #expect(farOver.reasons == [String(format: "Very slow HTTP (%.0fms)", limits.degraded + 1)])
    }

    // MARK: - Recovery hold

    @Test func recoveryHoldKeepsCleanReadingDegradedUntilStableForFullDuration() {
        var hold = RecoveryHold(duration: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        let clean = Self.reading()
        let slow = Self.reading(ping: 800)
        #expect(clean.state == .good)
        #expect(slow.state == .degraded)

        // No trouble seen yet: a clean reading passes straight through.
        #expect(hold.apply(clean, now: start) == clean)

        // Trouble takes effect at once and is shown unchanged.
        #expect(hold.apply(slow, now: start.addingTimeInterval(10)) == slow)

        let after5s = hold.apply(clean, now: start.addingTimeInterval(15))
        #expect(after5s.state == .degraded)
        #expect(after5s.isRecovering)
        #expect(after5s.ratingLabel == "Recovering")
        #expect(after5s.score == 67)
        #expect(after5s.reasons == ["Recovering (stable 5s of 60s)"])
        #expect(after5s.pingLatency == clean.pingLatency)
        #expect(after5s.httpLatency == clean.httpLatency)

        let justShort = hold.apply(clean, now: start.addingTimeInterval(69.9))
        #expect(justShort.state == .degraded)
        #expect(justShort.isRecovering)

        let served = hold.apply(clean, now: start.addingTimeInterval(70))
        #expect(served == clean)
        #expect(!served.isRecovering)

        #expect(hold.apply(clean, now: start.addingTimeInterval(75)) == clean)
    }

    @Test func troubleDuringRecoveryRestartsTheHold() {
        var hold = RecoveryHold(duration: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        let clean = Self.reading()
        let slow = Self.reading(ping: 800)

        _ = hold.apply(slow, now: start)
        #expect(hold.apply(clean, now: start.addingTimeInterval(30)).isRecovering)
        _ = hold.apply(slow, now: start.addingTimeInterval(40))

        // 70s after the first trouble but only 30s after the second.
        let stillHeld = hold.apply(clean, now: start.addingTimeInterval(70))
        #expect(stillHeld.state == .degraded)
        #expect(stillHeld.reasons.first == "Recovering (stable 30s of 60s)")

        #expect(hold.apply(clean, now: start.addingTimeInterval(100)).state == .good)
    }

    @Test func recoveryFromDisconnectedPassesThroughRecovering() {
        var hold = RecoveryHold(duration: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        let offline = Self.reading(http: nil)
        #expect(offline.state == .disconnected)

        #expect(hold.apply(offline, now: start).state == .disconnected)
        let back = hold.apply(Self.reading(), now: start.addingTimeInterval(5))
        #expect(back.state == .degraded)
        #expect(back.isRecovering)
        #expect(hold.apply(Self.reading(), now: start.addingTimeInterval(60)).state == .good)
    }

    @Test func recoveryHoldKeepsExistingReasonsAfterItsOwn() {
        var hold = RecoveryHold(duration: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = hold.apply(Self.reading(ping: 800), now: start)

        // Good, but carrying an informational jitter reason of its own.
        let jittery = NetworkHealth.evaluate(
            isConnected: true, pingLatency: 20, jitter: 30, recentPacketLoss: 0,
            httpLatency: 40, downloadSpeedMbps: nil,
            goodThreshold: 150, degradedThreshold: 600, isICMPBlocked: false
        )
        #expect(jittery.state == .good)
        let held = hold.apply(jittery, now: start.addingTimeInterval(20))
        #expect(held.reasons == ["Recovering (stable 20s of 60s)", "High jitter (±30ms)"])
    }

    @Test func intermittentLinkIsNeverShownGoodWhileItKeepsStalling() {
        // Every fourth 10s cycle is terrible. Judged one sample at a time this read Good 75% of the time.
        var hold = RecoveryHold(duration: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        var shownState = ConnectionState.good
        var rawStates: [ConnectionState] = []
        var shownStates: [ConnectionState] = []

        for cycle in 0..<16 {
            let stalled = cycle % 4 == 3
            let raw = Self.reading(ping: stalled ? 800 : 20, http: stalled ? 2_500 : 40, previousState: shownState)
            let shown = hold.apply(raw, now: start.addingTimeInterval(Double(cycle) * 10))
            rawStates.append(raw.state)
            shownStates.append(shown.state)
            shownState = shown.state
        }

        #expect(rawStates.filter { $0 == .good }.count == 12)
        #expect(shownStates.prefix(3).allSatisfy { $0 == .good })
        #expect(shownStates.dropFirst(3).allSatisfy { $0 == .degraded })
    }

    @Test func clockSetBackwardsDoesNotExtendTheHold() {
        var hold = RecoveryHold(duration: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = hold.apply(Self.reading(ping: 800), now: start)
        #expect(hold.apply(Self.reading(), now: start.addingTimeInterval(-30)).state == .good)
    }
}
