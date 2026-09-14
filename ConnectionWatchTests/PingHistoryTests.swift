import Foundation
import Testing

struct PingHistoryTests {
    @Test func appendsResults() {
        var history = PingHistory(capacity: 5)
        history.append(PingResult(timestamp: Date(), latency: 10))
        history.append(PingResult(timestamp: Date(), latency: 20))

        #expect(history.count == 2)
        #expect(history.latest?.latency == 20)
    }

    @Test func respectsCapacity() {
        var history = PingHistory(capacity: 3)
        for i in 1...5 {
            history.append(PingResult(timestamp: Date(), latency: Double(i * 10)))
        }

        #expect(history.count == 3)
        // Should contain the last 3 entries: 30, 40, 50
        let latencies = history.entries.compactMap(\.latency)
        #expect(latencies == [30, 40, 50])
    }

    @Test func calculatesAverage() {
        var history = PingHistory()
        history.append(PingResult(timestamp: Date(), latency: 10))
        history.append(PingResult(timestamp: Date(), latency: 30))
        history.append(PingResult(timestamp: Date(), latency: nil)) // failed

        #expect(history.averageLatency == 20.0)
    }

    @Test func calculatesMinMax() {
        var history = PingHistory()
        history.append(PingResult(timestamp: Date(), latency: 5))
        history.append(PingResult(timestamp: Date(), latency: 50))
        history.append(PingResult(timestamp: Date(), latency: 25))

        #expect(history.minLatency == 5)
        #expect(history.maxLatency == 50)
    }

    @Test func calculatesPacketLoss() {
        var history = PingHistory()
        history.append(PingResult(timestamp: Date(), latency: 10))
        history.append(PingResult(timestamp: Date(), latency: nil))
        history.append(PingResult(timestamp: Date(), latency: nil))
        history.append(PingResult(timestamp: Date(), latency: 20))

        #expect(history.packetLoss == 50.0)
    }

    @Test func icmpBlockedRecentPacketLossFallsBackToHTTP() {
        var history = PingHistory()

        // 1 or 2 failed pings + HTTP success should NOT classify as ICMP blocked yet
        history.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
        history.append(PingResult(timestamp: Date(), latency: 42.0, probeType: .http))
        #expect(history.isICMPLikelyBlocked == false)

        history.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
        history.append(PingResult(timestamp: Date(), latency: 42.0, probeType: .http))
        #expect(history.isICMPLikelyBlocked == false)

        // 3rd failed ping reaches minimum sample count for ICMP blocked classification
        history.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
        history.append(PingResult(timestamp: Date(), latency: 42.0, probeType: .http))
        #expect(history.isICMPLikelyBlocked == true)
        #expect(history.rawRecentPingPacketLoss() == 100.0)
        #expect(history.recentPacketLoss() == 0.0)
        #expect(history.averageLatency == 42.0)
    }

    @Test func emptyHistoryReturnsNilStats() {
        let history = PingHistory()
        #expect(history.averageLatency == nil)
        #expect(history.minLatency == nil)
        #expect(history.maxLatency == nil)
        #expect(history.packetLoss == 0)
        #expect(history.isEmpty)
    }

    @Test func clearRemovesAllEntries() {
        var history = PingHistory()
        history.append(PingResult(timestamp: Date(), latency: 10))
        history.append(PingResult(timestamp: Date(), latency: 20))
        history.clear()

        #expect(history.isEmpty)
        #expect(history.count == 0)
    }

    @Test func preservesSpeedEntryAcrossBufferEviction() {
        var history = PingHistory(capacity: 4)
        let speedResult = PingResult(
            timestamp: Date(),
            latency: 15.0,
            downloadSpeedMbps: 250.5,
            bytesTransferred: 10_000_000,
            probeType: .speed
        )
        history.append(speedResult)

        // Overflow ring buffer with regular ping/http probes
        for i in 1...10 {
            history.append(PingResult(timestamp: Date(), latency: Double(i), probeType: .ping))
        }

        #expect(history.count == 4)
        #expect(history.latestSpeed?.downloadSpeedMbps == 250.5)
        #expect(history.latestDownloadSpeedMbps == 250.5)
    }

    @Test func consecutiveHTTPFailuresClearICMPBlockedStatus() {
        var history = PingHistory()
        for _ in 0..<4 {
            history.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
            history.append(PingResult(timestamp: Date(), latency: 40.0, probeType: .http))
        }
        #expect(history.isICMPLikelyBlocked == true)

        // Single transient HTTP failure keeps isICMPLikelyBlocked true
        history.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
        history.append(PingResult(timestamp: Date(), latency: nil, probeType: .http))
        #expect(history.isICMPLikelyBlocked == true)

        // Second consecutive HTTP failure indicates actual outage, clearing isICMPLikelyBlocked
        history.append(PingResult(timestamp: Date(), latency: nil, packetLossPercent: 100.0, probeType: .ping))
        history.append(PingResult(timestamp: Date(), latency: nil, probeType: .http))
        #expect(history.isICMPLikelyBlocked == false)
    }
}
