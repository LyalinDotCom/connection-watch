import Foundation

struct PingHistory: Sendable {
    private var buffer: [PingResult]
    private let capacity: Int

    init(capacity: Int = 240) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    var entries: [PingResult] { buffer }
    var count: Int { buffer.count }
    var isEmpty: Bool { buffer.isEmpty }

    var latest: PingResult? { buffer.last }

    var latestPing: PingResult? { buffer.last { $0.probeType == .ping } }
    var latestHTTP: PingResult? { buffer.last { $0.probeType == .http } }

    func entries(ofType type: ProbeType) -> [PingResult] {
        buffer.filter { $0.probeType == type }
    }

    var successfulEntries: [PingResult] {
        buffer.filter { $0.succeeded }
    }

    var averageLatency: Double? {
        let latencies = buffer.compactMap(\.latency)
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var minLatency: Double? {
        buffer.compactMap(\.latency).min()
    }

    var maxLatency: Double? {
        buffer.compactMap(\.latency).max()
    }

    var packetLoss: Double {
        guard !buffer.isEmpty else { return 0 }
        let failed = buffer.filter { !$0.succeeded }.count
        return Double(failed) / Double(buffer.count) * 100
    }

    func averageLatency(ofType type: ProbeType) -> Double? {
        let latencies = buffer.filter { $0.probeType == type }.compactMap(\.latency)
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    mutating func append(_ result: PingResult) {
        if buffer.count >= capacity {
            buffer.removeFirst()
        }
        buffer.append(result)
    }

    mutating func clear() {
        buffer.removeAll(keepingCapacity: true)
    }
}
