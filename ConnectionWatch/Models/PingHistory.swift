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
    var latestSpeed: PingResult? { buffer.last { $0.probeType == .speed } }

    var latestDownloadSpeedMbps: Double? {
        buffer.last { $0.probeType == .speed && $0.downloadSpeedMbps != nil }?.downloadSpeedMbps
    }

    var latestJitter: Double? {
        latestPing?.jitter
    }

    func entries(ofType type: ProbeType) -> [PingResult] {
        buffer.filter { $0.probeType == type }
    }

    var successfulEntries: [PingResult] {
        buffer.filter { $0.succeeded }
    }

    var averageLatency: Double? {
        let latencies = buffer.filter { $0.probeType != .speed }.compactMap(\.latency)
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var minLatency: Double? {
        buffer.filter { $0.probeType != .speed }.compactMap(\.latency).min()
    }

    var maxLatency: Double? {
        buffer.filter { $0.probeType != .speed }.compactMap(\.latency).max()
    }

    var packetLoss: Double {
        let relevant = buffer.filter { $0.probeType != .speed }
        guard !relevant.isEmpty else { return 0 }
        let failed = relevant.filter { !$0.succeeded }.count
        return Double(failed) / Double(relevant.count) * 100
    }

    /// Calculates packet loss percentage over the most recent `window` ping probes
    /// so sudden network degradation is detected immediately.
    func recentPacketLoss(window: Int = 8) -> Double {
        let pingEntries = buffer.filter { $0.probeType == .ping }.suffix(window)
        guard !pingEntries.isEmpty else { return 0 }
        var totalLoss: Double = 0
        for entry in pingEntries {
            if let explicitLoss = entry.packetLossPercent {
                totalLoss += explicitLoss
            } else {
                totalLoss += entry.succeeded ? 0.0 : 100.0
            }
        }
        return totalLoss / Double(pingEntries.count)
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
