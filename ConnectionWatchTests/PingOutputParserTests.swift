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
}
