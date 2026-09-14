import Testing

struct PingOutputParserTests {
    @Test func parsesTypicalPingOutput() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=55 time=12.345 ms
        """
        let latency = PingOutputParser.parseLatency(from: output)
        #expect(latency == 12.345)
    }

    @Test func parsesIntegerLatency() {
        let output = "64 bytes from 1.1.1.1: icmp_seq=0 ttl=55 time=8 ms"
        let latency = PingOutputParser.parseLatency(from: output)
        #expect(latency == 8.0)
    }

    @Test func parsesHighLatency() {
        let output = "64 bytes from 1.1.1.1: icmp_seq=0 ttl=55 time=1234.56 ms"
        let latency = PingOutputParser.parseLatency(from: output)
        #expect(latency == 1234.56)
    }

    @Test func returnsNilForFailedPing() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        Request timeout for icmp_seq 0
        """
        let latency = PingOutputParser.parseLatency(from: output)
        #expect(latency == nil)
    }

    @Test func returnsNilForEmptyOutput() {
        let latency = PingOutputParser.parseLatency(from: "")
        #expect(latency == nil)
    }

    @Test func returnsNilForGarbageInput() {
        let latency = PingOutputParser.parseLatency(from: "not a ping output at all")
        #expect(latency == nil)
    }

    @Test func parsesSinglePacketNanStddevSummary() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=52 time=20.732 ms
        Request timeout for icmp_seq 1
        Request timeout for icmp_seq 2

        --- 1.1.1.1 ping statistics ---
        3 packets transmitted, 1 packets received, 66.7% packet loss
        round-trip min/avg/max/stddev = 20.732/20.732/20.732/nan ms
        """
        let summary = PingOutputParser.parseSummary(from: output)
        #expect(summary != nil)
        #expect(summary?.avgLatency == 20.732)
        #expect(summary?.jitter == 0.0)
        #expect(summary?.packetLossPercent == 66.7)
    }
}
