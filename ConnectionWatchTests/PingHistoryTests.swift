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
}
